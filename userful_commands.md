# List of useful commands

## Used to create the base image, run in folder with base Dockerfile
docker build -t custom-opencode:latest

## Used to access the running image, and have multiple sessions
docker exec -it <container-name> bash 