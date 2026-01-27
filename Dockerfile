FROM node:20-slim

WORKDIR /app

# Copy package files
COPY backend/package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY backend/ .

# Railway uses the PORT environment variable
# If PORT is not set, we default to 3000
ENV PORT=3000
EXPOSE 3000

# Start the application
CMD ["npm", "start"]
