#!/bin/bash

# Step 0: Install Python dependencies
echo "Installing Python dependencies..."
pip install -r requirements.txt

# Step 1: Run Terraform to create the Kafka cluster
echo "Initializing and applying Terraform..."
terraform init
terraform apply -auto-approve

# Step 2: Store the Kafka brokers in a JSON file
echo "Saving Kafka brokers in JSON file..."
terraform output -json > kafka_brokers.json

# Step 3: Extract the broker addresses from kafka_brokers.json
BROKER_LIST=$(jq -r '.kafka_bootstrap_servers.value' kafka_brokers.json)
echo "Extracted Kafka brokers: ${BROKER_LIST}"

# Step 4: Run the Python script to produce data to Kafka
echo "Running the Python script to produce data to Kafka..."
python3 python_kafka.py

# Step 5: Update the s3-sink.properties file with the extracted brokers
echo "Updating s3-sink.properties with the Kafka brokers..."
sed -i "s|bootstrap.servers=.*|bootstrap.servers=${BROKER_LIST}|g" /home/ec2-user/s3-sink.properties

# Step 6: Update connect-standalone.properties file with the extracted brokers
echo "Updating connect-standalone.properties with the Kafka brokers..."
sed -i "s|bootstrap.servers=.*|bootstrap.servers=${BROKER_LIST}|g" /home/ec2-user/kafka_2.12-3.5.1/config/connect-standalone.properties

# Step 7: Run the S3 Sink Connector to send Kafka data to S3
echo "Running Kafka Connect with S3 Sink connector..."
cd /home/ec2-user/kafka_2.12-3.5.1/
bin/connect-standalone.sh config/connect-standalone.properties /home/ec2-user/s3-sink.properties &

# Get the process ID of Kafka Connect
CONNECT_PID=$!
echo "Kafka Connect started with PID: ${CONNECT_PID}"

# Step 8: Monitor the offset for the topic until 500 records are reached
TOPIC="finance-data"
TARGET_OFFSET=498

echo "Monitoring the offset for topic '${TOPIC}' to reach ${TARGET_OFFSET} records..."
while true; do
    # Get the current offset for the topic
    CURRENT_OFFSET=$(/home/ec2-user/kafka_2.12-3.5.1/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list ${BROKER_LIST} --topic ${TOPIC} --time -1 | awk -F: '{sum += $3} END {print sum}')

    # Check if the current offset has reached or exceeded the target
    if [[ $CURRENT_OFFSET -ge $TARGET_OFFSET ]]; then
        echo "Target offset of ${TARGET_OFFSET} reached. Stopping Kafka Connect (PID: ${CONNECT_PID})..."
        # Stop Kafka Connect
        kill -TERM ${CONNECT_PID}
        break
    fi

    # Sleep for a few seconds before checking again
    sleep 10
done

# Step 9: Wait for Kafka Connect to fully stop
wait ${CONNECT_PID}

# Step 10: Run Terraform to create AWS Glue and Athena
cd /home/ec2-user/athena
echo "Initializing and applying Terraform for AWS Glue and Athena..."
terraform init
terraform apply -auto-approve

echo "Process complete!"
