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