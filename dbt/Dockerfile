# Use official Python base image
FROM python:3.10

# Set working dir
WORKDIR /app

# Copy code
COPY . /app

# Install dependencies
RUN pip install --upgrade pip && pip install -r requirements.txt

WORKDIR /app/igdb_data_transform

# Set the command to run when the Docker container starts
CMD ["dbt", "run"]
