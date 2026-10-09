"use strict";

const { DynamoDBClient, DescribeTableCommand } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, ScanCommand, BatchWriteCommand } = require("@aws-sdk/lib-dynamodb");
const { fromIni } = require("@aws-sdk/credential-providers");

function getArgValue(argv, name) {
  const idx = argv.indexOf(`--${name}`);
  if (idx === -1) return undefined;
  const value = argv[idx + 1];
  if (!value || value.startsWith("--")) return undefined;
  return value;
}

function hasFlag(argv, name) {
  return argv.includes(`--${name}`);
}

function chunk(array, size) {
  const out = [];
  for (let i = 0; i < array.length; i += size) out.push(array.slice(i, i + size));
  return out;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function defaultTableTemplates() {
  // Wallet tables are intentionally excluded (legacy system).
  return [
    "WizzUser_users_${env}",
    "WizzUser_addresses_${env}",
    "WizzUser_favorites_${env}",
  ];
}

function parseTableMaps(value) {
  if (!value) return [];
  return value
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((pair) => {
      const idx = pair.indexOf("=");
      if (idx === -1) return null;
      const src = pair.slice(0, idx).trim();
      const dst = pair.slice(idx + 1).trim();
      if (!src || !dst) return null;
      return { src, dst };
    })
    .filter(Boolean);
}

function resolveTemplates(templates, env) {
  return templates.map((t) => t.replace("${env}", env));
}

async function describeTable(ddbClient, tableName) {
  const res = await ddbClient.send(new DescribeTableCommand({ TableName: tableName }));
  return res.Table;
}

async function scanAll(docClient, tableName, maxItems, pageSize) {
  let items = [];
  let lastEvaluatedKey = undefined;
  while (true) {
    const remaining = maxItems > 0 ? Math.max(0, maxItems - items.length) : 0;
    const limit = maxItems > 0 ? Math.min(pageSize, remaining) : pageSize;

    const resp = await docClient.send(
      new ScanCommand({
        TableName: tableName,
        Limit: limit,
        ExclusiveStartKey: lastEvaluatedKey,
      })
    );

    if (resp.Items && resp.Items.length) items = items.concat(resp.Items);
    lastEvaluatedKey = resp.LastEvaluatedKey;

    if (maxItems > 0 && items.length >= maxItems) break;
    if (!lastEvaluatedKey) break;
  }
  return items;
}

async function batchWriteAll(docClient, tableName, items) {
  let totalWritten = 0;
  for (const batch of chunk(items, 25)) {
    let requestItems = {
      [tableName]: batch.map((Item) => ({ PutRequest: { Item } })),
    };

    let attempt = 0;
    while (true) {
      const resp = await docClient.send(new BatchWriteCommand({ RequestItems: requestItems }));
      const unprocessed = resp.UnprocessedItems && resp.UnprocessedItems[tableName];
      if (!unprocessed || unprocessed.length === 0) {
        totalWritten += batch.length;
        break;
      }

      attempt += 1;
      if (attempt > 10) {
        throw new Error(
          `Too many retries writing batch to ${tableName}. Unprocessed: ${unprocessed.length}`
        );
      }

      requestItems = { [tableName]: unprocessed };
      await sleep(200 * attempt);
    }
  }

  return totalWritten;
}

async function main() {
  const argv = process.argv.slice(2);

  const region = getArgValue(argv, "region") || "us-east-1";
  const sourceProfile = getArgValue(argv, "source-profile") || process.env.AWS_PROFILE;
  const targetProfile = getArgValue(argv, "target-profile") || process.env.AWS_PROFILE;
  const sourceEnv = getArgValue(argv, "source-env") || "dev";
  const targetEnv = getArgValue(argv, "target-env") || "staging";
  const maxItems = parseInt(getArgValue(argv, "max-items") || "0", 10); // 0 => no limit
  const pageSize = parseInt(getArgValue(argv, "page-size") || "200", 10);

  const write = hasFlag(argv, "write");
  const includeSensitive = hasFlag(argv, "include-sensitive");

  const tableMaps = parseTableMaps(getArgValue(argv, "table-maps"));

  if (!sourceProfile || !targetProfile) {
    console.error(
      "Missing profiles. Provide --source-profile and --target-profile (or set AWS_PROFILE)."
    );
    process.exit(2);
  }

  let templates = defaultTableTemplates();
  if (includeSensitive) {
    templates = templates.concat([
      "WizzUser_temp_users_${env}",
      "WizzUser_password_reset_tokens_${env}",
    ]);
  }

  let sourceTables;
  let targetTables;
  if (tableMaps.length) {
    sourceTables = tableMaps.map((m) => m.src);
    targetTables = tableMaps.map((m) => m.dst);
  } else {
    const tablesArg = getArgValue(argv, "tables");
    if (tablesArg) {
      templates = tablesArg
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    }

    sourceTables = resolveTemplates(templates, sourceEnv);
    targetTables = resolveTemplates(templates, targetEnv);
  }

  console.log("DynamoDB copy plan:");
  console.log(`- Region: ${region}`);
  console.log(`- Source: profile=${sourceProfile}, env=${sourceEnv}`);
  console.log(`- Target: profile=${targetProfile}, env=${targetEnv}`);
  console.log(`- Mode: ${write ? "WRITE" : "DRY-RUN"}`);
  console.log(`- Wallet tables: excluded by default`);
  console.log(`- Tables (${sourceTables.length}):`);
  for (let i = 0; i < sourceTables.length; i += 1) {
    console.log(`  - ${sourceTables[i]}  =>  ${targetTables[i]}`);
  }

  const sourceDdb = new DynamoDBClient({
    region,
    credentials: fromIni({ profile: sourceProfile }),
  });
  const targetDdb = new DynamoDBClient({
    region,
    credentials: fromIni({ profile: targetProfile }),
  });

  const sourceDoc = DynamoDBDocumentClient.from(sourceDdb);
  const targetDoc = DynamoDBDocumentClient.from(targetDdb);

  // Describe first (fast fail if a table doesn't exist)
  for (let i = 0; i < sourceTables.length; i += 1) {
    const srcName = sourceTables[i];
    const dstName = targetTables[i];

    const [srcDesc, dstDesc] = await Promise.all([
      describeTable(sourceDdb, srcName),
      describeTable(targetDdb, dstName),
    ]);

    console.log(
      `\nTable: ${srcName} -> ${dstName} | srcItemCount~${srcDesc.ItemCount} dstItemCount~${dstDesc.ItemCount}`
    );

    if (!write) continue;

    console.log(`Scanning source (${srcName})...`);
    const items = await scanAll(sourceDoc, srcName, maxItems, pageSize);
    console.log(`Scan complete: ${items.length} items`);

    if (items.length === 0) continue;

    console.log(`Writing to target (${dstName})...`);
    const written = await batchWriteAll(targetDoc, dstName, items);
    console.log(`Write complete: ${written} items`);
  }

  if (!write) {
    console.log("\nDry-run complete. Re-run with --write to copy items.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
