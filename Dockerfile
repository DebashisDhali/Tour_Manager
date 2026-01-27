FROM node:20

WORKDIR /app

# We are in the root directory (where backend/ is)
COPY backend/package*.json ./
RUN npm install

# Copy everything from backend/ to the current WORKDIR (/app)
COPY backend/ .

# Verify files are there
RUN ls -la

EXPOSE 3000

# Railway will provide the PORT env var. Our app handles it.
CMD ["node", "src/app_test.js"]
