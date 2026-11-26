# Staging region lookup correction

Android fresh address selection incorrectly displayed an unsupported-region dialog when the region resolver API returned HTTP 502. CloudWatch showed Runtime.ImportModuleError for aws-sdk before the handler ran. The resolver now uses DynamoDB SDK v3, with its H3 implementation bundled for the targeted Staging Lambda update. Source package dependencies reflect the SDK change for future builds.

The exact selected coordinates (31.8858445, 44.4803809) returned HTTP 200 and region Rmhveqa2vrrj13 after deployment. Region definitions, coverage, and IAM permissions were not changed.

Address-gate lookup now distinguishes server/network failures from a confirmed REGION_NOT_FOUND response; transient failures show an Arabic retry message rather than marking the address unserved. Three Dart tests cover HTTP 502, actual missing coverage, missing region metadata, and a successful lookup. Tests passed and Android APK was built. Google Places URL/key debug logging was removed from the affected screen.

The two restaurant-list Lambdas also failed on the same missing aws-sdk import. Their DynamoDB scans/batch reads now use SDK v3; the Staging code updates preserve existing environment, permissions and region filters. Live by-region requests returned HTTP 200 for both Rmhveqa2vrrj13 and Rmhvcpnn3iy5f1, and every returned item's regionId matched the requested region. Nearby lookup around the original coordinates returned HTTP 200 and five businesses. No business records or region assignments were modified.
