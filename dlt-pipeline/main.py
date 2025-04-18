import os
from flask import jsonify
import dlt
from dotenv import load_dotenv
from dlt.sources.helpers.rest_client.paginators import OffsetPaginator
from dlt.common.runtime.slack import send_slack_message
from dlt.sources.rest_api import (
    RESTAPIConfig,
    rest_api_resources
)

load_dotenv()

IGDB_CLIENT_ID = os.environ.get("IGDB_CLIENT_ID", "IGDB_CLIENT_ID environment variable is not set.")
IGDB_BEARER_TOKEN = os.environ.get("IGDB_BEARER_TOKEN", "IGDB_BEARER_TOKEN environment variable is not set.")
SLACK_INCOMING_HOOK = os.environ.get("SLACK_INCOMING_HOOK", "SLACK_INCOMING_HOOK environment variable is not set.")


@dlt.source(name="igdb", max_table_nesting=0)
def igdb_source():
    config: RESTAPIConfig = {
        "client": {
            "base_url": "https://api.igdb.com/v4/",
            "headers": {"Client-ID": IGDB_CLIENT_ID},
            "auth": (
                {
                    "type": "bearer",
                    "token": IGDB_BEARER_TOKEN,
                }
            ),
            "paginator": OffsetPaginator(
                offset_param="offset",
                limit=500,
                total_path=None,
                stop_after_empty_page=True,
            ),
        },
        "resource_defaults": {
            "endpoint": {
                "method": "POST",
                "params": {"fields": "*", "limit": 500},
            },
        },
        "resources": [
            {
                "name": "games",
                "endpoint": {
                    "path": "games",
                    "params": {
                        "fields": "*, cover.image_id, cover.url"
                    },
                },
            },
            "popularity_primitives",
            "popularity_types",
            "external_game_sources",
            "game_statuses",
            "game_types",
            "genres",
            "platforms"
        ],
    }

    yield from rest_api_resources(config)


def load_igdb(request):
    pipeline = dlt.pipeline(
        pipeline_name="igdb_dlt_pipeline",
        destination="filesystem",
        dataset_name="igdb_source",
        # progress="log"
    )

    load_info = pipeline.run(igdb_source(), loader_file_format="parquet")

    send_slack_message(SLACK_INCOMING_HOOK, str(load_info))
    print(load_info)
    return jsonify({"status": "success", "load_info": str(load_info)}), 200
