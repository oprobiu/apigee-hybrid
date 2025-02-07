# Apigee Hybrid Installer

## SUPPORT

This script is **NOT SUPPORTED** by the Google Cloud / Apigee Team. So don't bother them. Morever, I don't care if you find bugs. Don't bother me.

## PREREQUISITES

- helm v3.10.0+
- kubectl v3.10.0+
- Google Cloud SDK 498.0.0+
- jq v1.7+
- bash v5.0+

### COMPATIBILITY

- Apigee Hybrid v1.11.x -> v1.14.x

## HOW TO RUN

```bash
bash apigee-installer.sh [--help]                       
```

To install step-by-step:

```bash
bash apigee-installer.sh --manual                       
```

To install automatically:

```bash
bash apigee-installer.sh --auto                         
```

Debug mode:

```bash
bash apigee-installer.sh (--manual | --auto) --debug        # The flag will show the debug messages in stderr, however,
                                                            # even if it is not used, debug logs can still be seen in the logs.d files. 
```

## CONFIGURABLE VARIABLES

| Variable Name | Description    |
|-------------|-------------|
| PROJECT_ID | Your GCP project ID |
| ANALYTICS_REGION          | Needs to be part of the [listed regions](https://cloud.google.com/apigee/docs/locations). | 
| ENV_NAME                  | Name of the environment name that will be created.                     |
| ENV_GROUP                 | Name of the environment group that will be created. |
| DOMAIN                    | Can be replaced later. You can start with `example.com`.|
| CLUSTER_NAME              | Name of the cluster. |
| CLUSTER_LOCATION          | A valid location to host the GKE cluster on, [listed in the doc](https://cloud.google.com/compute/docs/regions-zones). |
| CLUSTER_NUM_NODES         | The number of nodes for ***EACH*** zone in the `CLUSTER_LOCATION` region. |
| CLUSTER_VERSION           | The GKE cluster version. |
| CLUSTER_MACHINE_TYPE      | The node machine type. |
| VPC_NETWORK               | The VPC network where the cluster will be deployed to.|
| CHART_VERSION             | The Helm Charts' version. Change this variable to install Apigee using a different version. For existing `userCache.json` files, change the version mentioned at `CHART_VERSION`. To permanently change the version, change the `CHART_VERSION` in the `CACHE_VARIABLES_JSON` variable, inside the `${JSON_VARIABLES_ENV}` file. |
| CERT_MANAGER_RELEASE      | The Cert Manager version. |
| CASSANDRA_REPLICA_COUNT   | The number of Cassandra nodes that will be installed in the cluster. |
| CASSANDRA_STORAGE_CAPACITY|   |
| CASSANDRA_REQUESTS_CPU    |   |
| CASSANDRA_REQUESTS_MEM    |   |
| CASSANDRA_MAX_HEAP_SIZE   |   |
| CASSANDRA_HEAP_NEW_SIZE   |   |
| INGRESS_NAME              | The name of the Apigee Ingress that will be used in the `overrides.yaml` file. |
| CASSANDRA_HOST_NETWORK    | The C* host network option. Default `false`. |
| OVERRIDES_FILE_NAME       |   |
| UNIQUE_INSTANCE_IDENTIFIER| Needs to be unique for each cluster. |
| ADMIN_EMAIL               | The email address of the account with Admin privileges.    |
| EXPOSE_INGRESS_GATEWAY    | `NONPROD` means that the default ingress will be used. `PROD` means that a custom ingress will be generated. |
| PROD_TYPE | The Installation production type. By default it is `NONPROD`, which corresponds to a `EVALUATION`. |


## NOTES / LIMITATIONS

- Only Apigee Hybrid `EVALUATION` installations are supported.
- Step `2.10: Check cluster readiness` was deprecated in Apigee Hybrid v1.13.
- Enabling WIF is not available yet.
- Production-like deployments are not avaiable yet.
- Custom Ingress Service is available for GKE.
- Data Residency is **not** available.

