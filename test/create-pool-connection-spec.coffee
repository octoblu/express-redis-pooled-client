async             = require 'async'
RedisNS           = require '@octoblu/redis-ns'
Redis             = require 'ioredis'
express           = require 'express'
enableDestroy     = require 'server-destroy'
request           = require 'request'
RedisPooledClient = require '..'

describe 'CreatePoolConnection', ->
  beforeEach 'redis', (done) ->
    @client = new RedisNS 'meshblu-test', new Redis 'redis://localhost:6379', dropBufferSupport: true
    @client.once 'ready', done
    @client.once 'error', done

  beforeEach 'sut', ->
    @sut = new RedisPooledClient {
      maxConnections: 3
      minConnections: 1
      namespace: 'meshblu-test'
      redisUri: 'redis://localhost:6379'
    }

  describe '->middleware', ->
    beforeEach (done) ->
      app = express()
      app.use @sut.middleware
      app.post '/block/:n', (request, response) =>
        { n } = request.params
        request.redisClient.brpop "empty-list", 1, (error, result) =>
          console.error error if error?
          return response.sendStatus(500) if error?
          return response.sendStatus(408) unless result?
          response.sendStatus(200)

      @server = app.listen undefined, (error) =>
        @port = @server.address().port
        done error
      enableDestroy @server

    it 'when using the client a lot', (done) ->
      @timeout 10000
      doneCount = 0
      async.times 3, (n, callback) =>
        request.post "http://localhost:#{@port}/block/#{n}", (error, response) =>
          return done error if error?
          expect(response.statusCode).to.equal 408
          doneCount++
          callback()
      , (error) =>
        return done error if error?
        expect(doneCount).to.equal 3
        done()


  describe 'validateAsync', ->
    beforeEach (done) ->
      @sut.pool.acquire (error, @client) =>
        return done error if error?
        @sut.pool.release @client
        @sut.pool.acquire (error, @client) =>
          done error

    it 'should get a client', ->
      expect(@client).to.exist
