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

  middleware: =>
    return (request, response, next) =>
      @pool.acquire (error, redisClient) =>
        return next error if error?
        request.redisClient = redisClient
        onFinished response, =>
          @pool.release redisClient
        next()

  proofoflife: =>
    return (request, response, next) =>
      request.redisClient.set 'test:write', Date.now(), (error) =>
        return response.status(error?.code ? 500).send error: error.message if error?
        response.send { online: true }

  _closeClient: (client) =>
    client.on 'error', (error) =>
      # silently ignore

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
        options = {
          dropBufferSupport: true,
        }
        client = new RedisNS namespace, redis.createClient redisUri, options
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
