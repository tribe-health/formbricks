FROM node:20-bookworm AS base

# Step 1: Install system dependencies
RUN apt-get update && apt-get install -y \
    g++ cmake make gcc python3 openssl jq curl \
    && rm -rf /var/lib/apt/lists/*

# Step 2: Set up base working directory and corepack for pnpm
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate

#
## Step 2: Install & build
#
FROM base AS installer

# Set hardcoded environment variables for the build stage
ENV DATABASE_URL="postgresql://placeholder:for@build:5432/gets_overwritten_at_runtime?schema=public"
ENV NEXTAUTH_SECRET="placeholder_for_next_auth_of_64_chars_get_overwritten_at_runtime"
ENV ENCRYPTION_KEY="placeholder_for_build_key_of_64_chars_get_overwritten_at_runtime"
ENV CRON_SECRET="placeholder_for_cron_secret_of_64_chars_get_overwritten_at_runtime"

# Set ARG values (these can be optionally passed during build)
ARG NEXT_PUBLIC_SENTRY_DSN
ARG SENTRY_AUTH_TOKEN

# Copy project files
COPY . .

# Create .env file if needed
RUN touch apps/web/.env

# Install dependencies with pnpm
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm install --frozen-lockfile

# Clear any existing node_modules and reinstall Prisma CLI
RUN rm -rf node_modules
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store pnpm add -D prisma zod-prisma-types -w

# Generate Prisma client with arm64 support
ENV PRISMA_CLIENT_ENGINE_TYPE=binary
RUN cd packages/database && npx prisma generate

# Build the project with pnpm, targeting only the @formbricks/web package
RUN pnpm build --filter "@formbricks/web..." 

# Add verification step to ensure standalone directory exists
RUN ls -la apps/web/.next/standalone || echo "Standalone directory not created"

# Extract Prisma version for later stages
RUN jq -r '.devDependencies.prisma' packages/database/package.json > /prisma_version.txt

#
## Step 3: Setup production runner
#
FROM base AS runner

# Enable corepack and install system dependencies for production
RUN corepack enable && apt-get update && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/* && adduser --system --uid 1001 nextjs

# Set working directory for production
WORKDIR /home/nextjs

# Copy only the necessary build output and configuration for a leaner image
COPY --from=installer /app/apps/web/next.config.mjs .
COPY --from=installer /app/apps/web/package.json .
COPY --from=installer --chown=nextjs:nextjs /app/apps/web/.next/standalone ./
COPY --from=installer --chown=nextjs:nextjs /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=installer --chown=nextjs:nextjs /app/apps/web/public ./apps/web/public
COPY --from=installer --chown=nextjs:nextjs /app/packages/database/schema.prisma ./packages/database/schema.prisma
COPY --from=installer --chown=nextjs:nextjs /app/packages/database/package.json ./packages/database/package.json
COPY --from=installer --chown=nextjs:nextjs /app/packages/database/migrations ./packages/database/migrations
COPY --from=installer --chown=nextjs:nextjs /prisma_version.txt .
COPY /docker/cronjobs /app/docker/cronjobs

# Install Prisma globally using the version saved during build
RUN PRISMA_VERSION=$(cat prisma_version.txt) && npm install -g prisma@$PRISMA_VERSION

# Expose necessary ports and set default environment variables
EXPOSE 3000
ENV HOSTNAME="0.0.0.0"

# Prepare volume for uploads
RUN mkdir -p /home/nextjs/apps/web/uploads/
VOLUME /home/nextjs/apps/web/uploads/

# Start the application with cron jobs and migrations
CMD supercronic -quiet /app/docker/cronjobs & \
    (cd packages/database && npm run db:migrate:deploy) && \
    exec node apps/web/server.js