FROM node:18-alpine

WORKDIR /app

# Copy the backend directory contents into the container
COPY backend/package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of the backend code
COPY backend/ .

# Expose the port the app runs on
EXPOSE 3000

# Start the application
CMD ["npm", "start"]
