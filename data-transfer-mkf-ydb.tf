# Infrastructure for the Yandex Cloud YDB, Managed Service for Apache Kafka®, and Data Transfer
#
# RU: https://yandex.cloud/ru/docs/data-transfer/tutorials/mkf-to-ydb
# EN: https://yandex.cloud/en/docs/data-transfer/tutorials/mkf-to-ydb
#
# Configure the parameters of the source and target clusters:

locals {
  # Source Managed Service for Apache Kafka® cluster settings:
  source_kf_version    = "" # Apache Kafka® cluster version
  source_user_name     = "" # Username of the Apache Kafka® cluster
  source_user_password = "" # Apache Kafka® user's password

  # Target YDB settings:
  target_db_name = "" # YDB database name

  # Specify these settings ONLY AFTER the clusters are created. Then run "terraform apply" command again.
  # You should set up endpoints using the GUI to obtain their IDs
  source_endpoint_id = "" # Set the source endpoint ID
  target_endpoint_id = "" # Set the target endpoint ID
  transfer_enabled   = 0  # Set to 1 to enable the transfer

  # The following settings are predefined. Change them only if necessary.
  network_name        = "network"                  # Name of the network
  subnet_name         = "subnet-a"                 # Name of the subnet
  source_cluster_name = "kafka-cluster"            # Name of the Apache Kafka® cluster
  source_topic        = "sensors"                  # Name of the Apache Kafka® topic
  transfer_name       = "transfer-from-mkf-to-ydb" # Name of the transfer from the Managed Service for Apache Kafka® to the YDB database
}

# Network infrastructure

resource "yandex_vpc_network" "network" {
  description = "Network for the Managed Service for Apache Kafka® cluster and the YDB database"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.1.0.0/16"]
}

resource "yandex_vpc_default_security_group" "security-group" {
  description = "Security group for the Managed Service for Apache Kafka® cluster and the YDB database"
  network_id  = yandex_vpc_network.network.id

  ingress {
    protocol       = "TCP"
    description    = "Allow connections to the Managed Service for Apache Kafka® cluster from the Internet"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    description    = "Allow outgoing connections to any required resource"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Infrastructure for the Managed Service for Apache Kafka® cluster

resource "yandex_mdb_kafka_cluster" "kafka-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  name               = local.source_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_default_security_group.security-group.id]

  config {
    assign_public_ip = true
    brokers_count    = 1
    version          = local.source_kf_version
    zones            = ["ru-central1-a"]
    kafka {
      resources {
        resource_preset_id = "s2.micro"
        disk_type_id       = "network-hdd"
        disk_size          = 10 # GB
      }
    }
  }

  depends_on = [
    yandex_vpc_subnet.subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_topic" "sensors" {
  cluster_id         = yandex_mdb_kafka_cluster.kafka-cluster.id
  name               = local.source_topic
  partitions         = 4
  replication_factor = 1
}

# User of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "mkf-user" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-cluster.id
  name       = local.source_user_name
  password   = local.source_user_password
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# Infrastructure for the Yandex Database

resource "yandex_ydb_database_serverless" "ydb" {
  name = local.target_db_name
  location_id = "ru-central1"
}

# Data Transfer infrastructure

resource "yandex_datatransfer_transfer" "mkf-ydb-transfer" {
  description = "Transfer from the Managed Service for Apache Kafka® to the YDB database"
  count       = local.transfer_enabled
  name        = local.transfer_name
  source_id   = local.source_endpoint_id
  target_id   = local.target_endpoint_id
  type        = "INCREMENT_ONLY" # Replication data
}
