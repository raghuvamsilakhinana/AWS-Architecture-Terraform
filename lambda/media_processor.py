"""
Portfolio scaffold for an S3 -> Lambda media-processing path.

This is intentionally a safe reference implementation. Real video transcoding
would normally use AWS Elemental MediaConvert or a Lambda container/layer with
FFmpeg rather than trying to process large videos inside a small Lambda.
"""

import os
import urllib.parse
import boto3

s3 = boto3.client("s3")


def lambda_handler(event, context):
    bucket = os.environ["BUCKET"]

    for record in event.get("Records", []):
        if record.get("eventSource") != "aws:s3":
            continue

        source_bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        print({
            "message": "Media object received",
            "source_bucket": source_bucket,
            "key": key,
            "target_bucket": bucket,
        })

    return {"statusCode": 200, "processed": len(event.get("Records", []))}
