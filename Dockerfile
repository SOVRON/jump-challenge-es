# Multi-stage Dockerfile for Phoenix/LiveView application

# Build stage
FROM elixir:1.18.4-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base npm git python3 make g++ nodejs

# Prepare build directory
WORKDIR /app

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod

# Copy source code
COPY . .

# Build static assets and compile application in production mode
RUN MIX_ENV=prod mix assets.deploy && \
    MIX_ENV=prod mix compile

# Prepare release
RUN MIX_ENV=prod mix release

# Application stage
FROM elixir:1.18.4-alpine AS app

# Install runtime dependencies
RUN apk add --no-cache postgresql-client curl

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Create non-root user
RUN addgroup -g 1000 -S app && \
    adduser -u 1000 -S app -G app

# Prepare app directory
WORKDIR /app

# Copy built release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/jump ./

# Change to app user
USER app

# Set Phoenix server environment variables
ENV PHX_SERVER=true
ENV PORT=4000

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Expose port
EXPOSE 4000

# Start the application
CMD ["bin/jump", "start"]
