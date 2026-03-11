-- ClickHouse Initialization Script
-- This script runs automatically when ClickHouse starts for the first time
-- Purpose: Create the netflow database and test database

-- Create the main netflow database
CREATE DATABASE IF NOT EXISTS netflow;

-- Create a test database for testing purposes
CREATE DATABASE IF NOT EXISTS test;

-- Display databases
SHOW DATABASES;
