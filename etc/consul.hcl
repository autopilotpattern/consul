bind_addr = "0.0.0.0"
datacenter = "CONSUL_DATACENTER_NAME"
data_dir = "/data"
client_addr = "0.0.0.0"
ports {
  dns = 53
  HTTP_PORT
  HTTPS_PORT
}
addresses {
  HTTP_ADDR
  HTTPS_ADDR
}
recursors = ["8.8.8.8", "8.8.4.4"]
disable_update_check = true
