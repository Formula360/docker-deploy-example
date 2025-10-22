# --- Stage 1: Builder Stage (Use for installing all dependencies) ---
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package.json and package-lock.json first to leverage caching
COPY package*.json ./

# Install ALL dependencies (dev and prod) for building
RUN npm install

# Copy the rest of the application code
COPY . .

# --- Stage 2: Production Stage (Clean, minimal final image) ---
FROM node:18-alpine AS production

WORKDIR /usr/src/app

# [FIX] Install 'curl' for the health check (it's not included in alpine by default)
RUN apk add --no-cache curl

# Copy only production files and dependencies from the builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app .

# Expose the port
EXPOSE 3000

# Perform the health check using the installed 'curl'
# Note: Changed to curl -f (fail silent on error)
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s \
    CMD curl -f http://127.0.0.1:3000/ || exit 1

# Command to start the application
<<<<<<< HEAD
CMD ["npm", "start"]
=======
CMD ["npm", "start"]
>>>>>>> d9aeef5 (Create multi-stage Dockerfile for app deployment)
