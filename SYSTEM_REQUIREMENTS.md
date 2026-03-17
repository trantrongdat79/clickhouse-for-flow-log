# System Requirements

## Hardware Requirements

### Minimum (for testing)
- **CPU**: 2 cores
- **RAM**: 4 GB
- **Disk**: 20 GB free space
- **Network**: Internet connection for pulling Docker images

### Recommended (for realistic testing)
- **CPU**: 4+ cores
- **RAM**: 8 GB
- **Disk**: 50 GB free space (SSD preferred)
- **Network**: 100 Mbps+ for faster image pulls

## Software Requirements

### Required
1. **Operating System**
   - Ubuntu 20.04 LTS or later (recommended)
   - Debian 11+ 
   - Other Linux distributions should work but are untested
   - Windows/macOS: Should work with Docker Desktop but untested

2. **Docker**
   - Version: 20.10.0 or later
   - Installation: https://docs.docker.com/engine/install/ubuntu/
   ```bash
   # Ubuntu/Debian installation
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER
   # Re-login for group changes to take effect
   ```

3. **Docker Compose**
   - Version: 2.0.0 or later (comes with Docker Desktop, or install separately)
   ```bash
   # Check version
   docker compose version
   
   # If not installed, install docker-compose-plugin
   sudo apt-get update
   sudo apt-get install docker-compose-plugin
   ```

4. **Python 3**
   - Version: 3.8 or later
   - Should be pre-installed on Ubuntu
   ```bash
   python3 --version
   ```

5. **pip (Python package manager)**
   ```bash
   sudo apt-get install python3-pip
   ```

### Optional (Helpful)
- **Git**: For cloning the repository
  ```bash
  sudo apt-get install git
  ```

- **curl**: For API testing
  ```bash
  sudo apt-get install curl
  ```

- **jq**: For JSON parsing in scripts
  ```bash
  sudo apt-get install jq
  ```

## Port Requirements

The following ports must be available on your host:

- **8123**: ClickHouse HTTP interface
- **9000**: ClickHouse native protocol
- **8086**: InfluxDB HTTP API
- **3000**: Grafana web interface

Check if ports are available:
```bash
sudo netstat -tulpn | grep -E ':(8123|9000|8086|3000)'
```

If ports are in use, you can change them in `docker/.env`

## Disk Space Planning

### Data Storage Estimates
- **Docker images**: ~2 GB
- **Sample data (1M records)**: ~500 MB
- **ClickHouse data**: ~200 MB (compressed)
- **InfluxDB data**: ~300 MB
- **Logs**: ~50 MB
- **Total for testing**: ~3.5 GB

### For Large-Scale Testing (100M records)
- **Raw data**: ~50 GB
- **ClickHouse**: ~20 GB (compressed)
- **InfluxDB**: ~30 GB
- **Total**: ~100 GB recommended

## Verification

After installing requirements, verify:

```bash
# 1. Check Docker
docker --version
docker compose version
docker ps  # Should not error

# 2. Check Python
python3 --version
pip3 --version

# 3. Check disk space
df -h

# 4. Check available ports
sudo netstat -tulpn | grep -E ':(8123|9000|8086|3000)'
# Should return nothing (ports free)
```

## Troubleshooting

### Docker Permission Denied
```bash
sudo usermod -aG docker $USER
# Then logout and login again
```

### Python command not found
```bash
sudo apt-get update
sudo apt-get install python3 python3-pip
```

### Insufficient disk space
```bash
# Clean Docker
docker system prune -a --volumes
```

## Cloud Deployment

If deploying on cloud (AWS, GCP, Azure):

- **Instance Type**: t3.medium or equivalent (2 vCPU, 4GB RAM minimum)
- **Storage**: 20+ GB SSD
- **Security Groups**: Open ports 8123, 9000, 8086, 3000 (or use SSH tunneling)
- **OS Image**: Ubuntu 22.04 LTS recommended
