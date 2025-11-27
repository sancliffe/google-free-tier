# Use an official Node.js runtime as a parent image
FROM node:18-slim

# Set the working directory in the container
WORKDIR /usr/src/app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install app dependencies
# CHANGED: Use 'npm install' instead of 'npm ci' so the build works
# even if package-lock.json is missing.
RUN npm install --only=production

# Bundle app source
# Change ownership of the files to the 'node' user
COPY --chown=node:node . .

# Switch to the non-root 'node' user for security
USER node

# Your app binds to port 8080, so expose it
EXPOSE 8080

# Define the command to run your app
CMD [ "node", "server.js" ]