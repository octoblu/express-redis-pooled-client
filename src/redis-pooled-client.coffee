{Pool}     = require '@octoblu/generic-pool'
RedisNS    = require '@octoblu/redis-ns'
redis      = require 'ioredis'
onFinished = require 'on-finished'

class RedisPooledClient
  constructor: (options={}) ->
    {
      maxConnections
      minConnections
      idleTimeoutMillis
      namespace
      redisUri
    } = options

    minConnections ?= 1
    idleTimeoutMillis ?= 60000

    throw new Error('RedisPooledJobManager: maxConnections is required') unless maxConnections?
    throw new Error('RedisPooledJobManager: namespace is required') unless namespace?
    throw new Error('RedisPooledJobManager: redisUri is required') unless redisUri?

    @pool = @_createPool {maxConnections, minConnections, idleTimeoutMillis, namespace, redisUri}

  middleware: (request, response, next) =>
    @pool.acquire (error, redisClient) =>
      return next error if error?
      request.redisClient = redisClient
      onFinished response, =>
        @pool.release redisClient
      next()

  _closeClient: (client) =>
    client.on 'error', =>
      # silently deal with it

    try
      if client.disconnect?
        client.quit()
        client.disconnect false
        return

      client.end true
    catch

  _createPool: ({maxConnections, minConnections, idleTimeoutMillis, namespace, redisUri}) =>
    return new Pool
      max: maxConnections
      min: minConnections
      idleTimeoutMillis: idleTimeoutMillis
      create: (callback) =>
        client = new RedisNS namespace, redis.createClient redisUri, dropBufferSupport: true
        client.ping (error) =>
          return callback error if error?
          client.once 'error', (error) =>
            @_closeClient client

          callback null, client

      destroy: @_closeClient

      validateAsync: (client, callback) =>
        client.ping (error) =>
          return callback false if error?
          callback true

module.exports = RedisPooledClient
