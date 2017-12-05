bind_addr = "CONTAINERPILOT_CONSUL_IP"
data_dir = "/data"
client_addr = "0.0.0.0"
ports {
  dns = 53
}
recursors = ["8.8.8.8", "8.8.4.4"]
disable_update_check = true
