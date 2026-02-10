#!/bin/bash

# Configuration
AMI_ID="ami-0220d79f3f480ecf5"
SG_ID="sg-0e1a85cce60125dcd"
ZONE_ID="Z07554052DKE460EXL8MZ"
DOMAIN_NAME="devops26.online"

# script_name mangodb catalogue frontend user cart shipping payment dispatch

if [ -z "$1" ]; then
    echo "Error: The input parameter is null or empty."
    exit 1
fi

for instance in "$@"; do
    echo "--- Launching $instance ---"

    # 1. Launch Instance & Capture ID
    # Note: Corrected the query path for run-instances (no 'Reservations' key)
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t2.micro \
        --security-group-ids "$SG_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "Created Instance: $INSTANCE_ID"

    # 2. CRITICAL: Wait for the instance to be ready
    # Without this, the IP address will be 'None'
    echo "Waiting for IP assignment..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    # 3. Determine IP and Record Name
    if [ "$instance" == "frontend" ]; then
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        RECORD_NAME="$DOMAIN_NAME"
    else
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
        RECORD_NAME="$instance.$DOMAIN_NAME"
    fi

    echo "Resolved IP for $instance: $IP"

    # 4. Update Route 53 (Using a heredoc for cleaner JSON)
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "{
        \"Comment\": \"Updating record set for $instance\",
        \"Changes\": [{
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
                \"Name\": \"$RECORD_NAME\",
                \"Type\": \"A\",
                \"TTL\": 1,
                \"ResourceRecords\": [{\"Value\": \"$IP\"}]
            }
        }]
    }" > /dev/null

    echo "DNS Updated: $RECORD_NAME -> $IP"
done