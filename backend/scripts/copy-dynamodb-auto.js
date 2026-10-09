"use strict";

const {
  DynamoDBClient,
  ListTablesCommand,
  DescribeTableCommand,
} = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  ScanCommand,
  BatchWriteCommand,
} = require("@aws-sdk/lib-dynamodb");
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

function stripNulls(value) {
  if (value === null || value === undefined) return undefined;

  if (Array.isArray(value)) {
    const mapped = value
      .map((v) => stripNulls(v))
      .filter((v) => v !== undefined);
    return mapped;
  }

  if (typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      const cleaned = stripNulls(v);
      if (cleaned !== undefined) out[k] = cleaned;
    }
    return out;
  }

  return value;
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function compileRegexList(csvOrEmpty) {
  if (!csvOrEmpty) return [];
  return csvOrEmpty
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((pattern) => new RegExp(pattern));
}

function matchesAny(name, regexes) {
  return regexes.some((re) => re.test(name));
}

function defaultExcludeRegexes() {
  // Safe-by-default exclusions: auth tokens, ephemeral sockets, wallet/ledger, idempotency, temp tables.
  return [
    /password_reset_tokens/i,
    /temp_users/i,
    /^websocket[-_]/i,
    /websocket_connections/i,
    /websocket_subscriptions/i,
    /^Chat(Sessions|Messages)$/i,
    /^chat-(sessions|messages)-/i,
    /IdempotencyKeys/i,
    /AuditLog/i,
    /Ledger/i,
    /Topup/i,
    /Holds/i,
    /Wallet/i,
  ];
}

function inferTargetNameFromSource(sourceName) {
  // Common env naming conversions
  const rules = [
    { from: /_dev$/i, to: "_staging" },
    { from: /-dev$/i, to: "-staging" },
    { from: /^dev-/i, to: "staging-" },
    { from: /_dev_/i, to: "_staging_" },
    { from: /-dev-/i, to: "-staging-" },

    // Some stacks use *_dev / *_staging for core app tables
    { from: /_dev$/i, to: "_staging" },
  ];

  for (const r of rules) {
    if (r.from.test(sourceName)) return sourceName.replace(r.from, r.to);
  }

  // If there's no env marker, assume same name in staging (shared tables across env accounts).
  return sourceName;
}

async function listAllTables(ddb) {
  let tableNames = [];
  let lastEvaluatedTableName = undefined;

  while (true) {
    const resp = await ddb.send(
      new ListTablesCommand({
        ExclusiveStartTableName: lastEvaluatedTableName,
        Limit: 100,
      })
    );

    if (resp.TableNames && resp.TableNames.length) {
      tableNames = tableNames.concat(resp.TableNames);
    }

    lastEvaluatedTableName = resp.LastEvaluatedTableName;
    if (!lastEvaluatedTableName) break;
  }

  return tableNames.sort((a, b) => a.localeCompare(b));
}

async function describeTable(ddb, tableName) {
  const res = await ddb.send(new DescribeTableCommand({ TableName: tableName }));
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
      [tableName]: batch
        .map((Item) => stripNulls(Item))
        .filter((Item) => Item !== undefined)
        .map((Item) => ({ PutRequest: { Item } })),
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

function keySchemaSignature(desc) {
  const ks = (desc.KeySchema || []).map((k) => `${k.AttributeName}:${k.KeyType}`).join(",");
  const attrs = (desc.AttributeDefinitions || []).map((a) => `${a.AttributeName}:${a.AttributeType}`).join(",");
  return `KS[${ks}] AD[${attrs}]`;
}

function primaryKeySignature(desc) {
  const defMap = new Map(
    (desc.AttributeDefinitions || []).map((a) => [a.AttributeName, a.AttributeType])
  );
  const ks = (desc.KeySchema || [])
    .map((k) => {
      const t = defMap.get(k.AttributeName) || "?";
      return `${k.AttributeName}:${k.KeyType}:${t}`;
    })
    .join(",");
  return `PK[${ks}]`;
}

async function main() {
  const argv = process.argv.slice(2);

  const region = getArgValue(argv, "region") || "us-east-1";
  const sourceProfile = getArgValue(argv, "source-profile") || process.env.AWS_PROFILE;
  const targetProfile = getArgValue(argv, "target-profile") || process.env.AWS_PROFILE;

  const write = hasFlag(argv, "write");
  const allowIndexMismatch = hasFlag(argv, "allow-index-mismatch");
  const maxItems = parseInt(getArgValue(argv, "max-items") || "0", 10);
  const pageSize = parseInt(getArgValue(argv, "page-size") || "200", 10);

  const includeRegexes = compileRegexList(getArgValue(argv, "include"));
  const excludeRegexes = defaultExcludeRegexes().concat(compileRegexList(getArgValue(argv, "exclude")));

  if (!sourceProfile || !targetProfile) {
    console.error(
      "Missing profiles. Provide --source-profile and --target-profile (or set AWS_PROFILE)."
    );
    process.exit(2);
  }

  const sourceDdb = new DynamoDBClient({ region, credentials: fromIni({ profile: sourceProfile }) });
  const targetDdb = new DynamoDBClient({ region, credentials: fromIni({ profile: targetProfile }) });
  const sourceDoc = DynamoDBDocumentClient.from(sourceDdb);
  const targetDoc = DynamoDBDocumentClient.from(targetDdb);

  const [sourceTables, targetTables] = await Promise.all([
    listAllTables(sourceDdb),
    listAllTables(targetDdb),
  ]);

  const targetSet = new Set(targetTables);

  // Filter source tables
  let filteredSource = sourceTables;
  if (includeRegexes.length) {
    filteredSource = filteredSource.filter((t) => matchesAny(t, includeRegexes));
  }
  filteredSource = filteredSource.filter((t) => !matchesAny(t, excludeRegexes));

  const mapping = [];
  const unmapped = [];

  for (const src of filteredSource) {
    const guessedTarget = inferTargetNameFromSource(src);
    if (targetSet.has(guessedTarget)) {
      mapping.push({ src, dst: guessedTarget });
    } else {
      unmapped.push({ src, guessedTarget });
    }
  }

  console.log("DynamoDB auto copy plan:");
  console.log(`- Region: ${region}`);
  console.log(`- Source profile: ${sourceProfile} (tables=${sourceTables.length}, selected=${filteredSource.length})`);
  console.log(`- Target profile: ${targetProfile} (tables=${targetTables.length})`);
  console.log(`- Mode: ${write ? "WRITE" : "DRY-RUN"}`);
  console.log(`- Schema check: ${allowIndexMismatch ? "PRIMARY_KEY_ONLY" : "STRICT"}`);
  console.log(`- Exclusions (default): ${defaultExcludeRegexes().map((r) => r.toString()).join(" ")}`);
  if (includeRegexes.length) console.log(`- Include: ${includeRegexes.map((r) => r.toString()).join(" ")}`);
  if (getArgValue(argv, "exclude")) console.log(`- Exclude extra: ${compileRegexList(getArgValue(argv, "exclude")).map((r) => r.toString()).join(" ")}`);

  console.log(`\nMapped tables (${mapping.length}):`);
  mapping.slice(0, 200).forEach((m) => console.log(`- ${m.src} -> ${m.dst}`));
  if (mapping.length > 200) console.log(`... (${mapping.length - 200} more)`);

  if (unmapped.length) {
    console.log(`\nUnmapped source tables (${unmapped.length}) (need explicit mapping or create target tables):`);
    unmapped.slice(0, 200).forEach((u) => console.log(`- ${u.src} (guessed ${u.guessedTarget})`));
    if (unmapped.length > 200) console.log(`... (${unmapped.length - 200} more)`);
  }

  // Describe + (optional) copy
  for (const { src, dst } of mapping) {
    const [srcDesc, dstDesc] = await Promise.all([
      describeTable(sourceDdb, src),
      describeTable(targetDdb, dst),
    ]);

    const srcSig = keySchemaSignature(srcDesc);
    const dstSig = keySchemaSignature(dstDesc);

    const srcPkSig = primaryKeySignature(srcDesc);
    const dstPkSig = primaryKeySignature(dstDesc);

    const schemaOk = allowIndexMismatch ? srcPkSig === dstPkSig : srcSig === dstSig;

    console.log(
      `\nTable: ${src} -> ${dst}` +
        `\n- srcItemCount~${srcDesc.ItemCount} dstItemCount~${dstDesc.ItemCount}` +
        `\n- schemaMatch: ${schemaOk ? "YES" : "NO"}`
    );

    if (!schemaOk) {
      if (allowIndexMismatch) {
        console.log(`- srcPrimaryKey: ${srcPkSig}`);
        console.log(`- dstPrimaryKey: ${dstPkSig}`);
        console.log(`- srcSchemaStrict: ${srcSig}`);
        console.log(`- dstSchemaStrict: ${dstSig}`);
      } else {
        console.log(`- srcSchema: ${srcSig}`);
        console.log(`- dstSchema: ${dstSig}`);
      }
      console.log("- SKIP (schema mismatch)");
      continue;
    }

    if (!write) continue;

    console.log(`Scanning source (${src})...`);
    const items = await scanAll(sourceDoc, src, maxItems, pageSize);
    console.log(`Scan complete: ${items.length} items`);

    if (items.length === 0) continue;

    console.log(`Writing to target (${dst})...`);
    const written = await batchWriteAll(targetDoc, dst, items);
    console.log(`Write complete: ${written} items`);
  }

  if (!write) {
    console.log("\nDry-run complete. Re-run with --write to copy items.");
    console.log("Tip: start with a narrow include, e.g. --include '^(WhizzMerchants_|WizzCentral_Regions$|WizzCentral_Region.*_dev$)' and then expand.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
