_              = require 'lodash'
mongojs        = require 'mongojs'
redis          = require 'ioredis'
async          = require 'async'
bcrypt         = require 'bcrypt'
RedisNS        = require '@octoblu/redis-ns'

TestDispatcher = require './test-dispatcher'
JobManager     = require 'meshblu-core-job-manager'
HydrantManager = require 'meshblu-core-manager-hydrant'

describe 'SendMessage2: send', ->
  beforeEach (done) ->
    @db            = mongojs 'meshblu-core-test'
    @devices    = @db.collection 'devices'
    @subscriptions = @db.collection 'subscriptions'
    @uuidAliasResolver =
      resolve: (uuid, callback) =>
        callback null, uuid

    @subscriptions.drop =>
      @devices.drop =>
        done()

  beforeEach (done) ->
    @redisUri = process.env.REDIS_URI
    @dispatcher = new TestDispatcher
    client = new RedisNS 'meshblu-test', redis.createClient(@redisUri)
    client.del 'request:queue', done

  beforeEach 'create sender device', (done) ->
    @auth =
      uuid: 'sender-uuid'
      token: 'leak'

    @senderDevice =
      uuid: 'sender-uuid'
      type: 'device:sender'
      token: bcrypt.hashSync @auth.token, 8
      meshblu:
        version: '2.0.0'
        whitelists:
          message:
            sent: 'spy-uuid': {}

    @devices.insert @senderDevice, done

  beforeEach 'create receiver device', (done) ->
    @receiverDevice =
      uuid: 'receiver-uuid'
      type: 'device:receiver'
      meshblu:
        version: '2.0.0'
        whitelists:
          message:
            from: 'sender-uuid': {}
            received: 'nsa-uuid': {}

    @devices.insert @receiverDevice, done

  beforeEach 'create spy device', (done) ->
    @spyDevice =
      uuid: 'spy-uuid'
      type: 'device:spy'

    @devices.insert @spyDevice, done

  beforeEach 'create nsa device', (done) ->
    @nsaDevice =
      uuid: 'nsa-uuid'
      type: 'device:nsa'

    @devices.insert @nsaDevice, done

  context 'When sending a message to another device', ->
    context "sender-uuid receiving its sent messages", ->
      @timeout 5000
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.sent'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'sender-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'sender-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        doneTwice = _.after 2, done
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage2'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        client = new RedisNS 'messages', redis.createClient(@redisUri)
        @hydrant = new HydrantManager {client, @uuidAliasResolver}
        @hydrant.connect uuid: @auth.uuid, (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            doneTwice()

          @dispatcher.generateJobs job, (error, @generatedJobs) => doneTwice()

      it 'should deliver the sent message to the sender', ->
        expect(@message).to.exist

    context 'receiving a direct message', ->
      @timeout 5000
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'receiver-uuid'
          subscriberUuid: 'receiver-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        doneTwice = _.after 2, done
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage2'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        client = new RedisNS 'messages', redis.createClient(@redisUri)
        @hydrant = new HydrantManager {client, @uuidAliasResolver}
        @hydrant.connect uuid: 'receiver-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            doneTwice()

          @dispatcher.generateJobs job, (error, @generatedJobs) => doneTwice()

      it 'should deliver the sent message to the receiver', ->
        expect(@message).to.exist

    context 'subscribed to someone elses sent messages', ->
      @timeout 5000
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.sent'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'spy-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        doneTwice = _.after 2, done
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage2'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        client = new RedisNS 'messages', redis.createClient(@redisUri)
        @hydrant = new HydrantManager {client, @uuidAliasResolver}
        @hydrant.connect uuid: 'spy-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            doneTwice()

          @dispatcher.generateJobs job, (error, @generatedJobs) => doneTwice()

      it 'should deliver the sent message to the receiver', ->
        expect(@message).to.exist

    context 'subscribed to someone elses sent messages, but is not authorized', ->
      @timeout 5000
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.sent'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'nsa-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage2'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        client = new RedisNS 'messages', redis.createClient(@redisUri)
        @hydrant = new HydrantManager {client, @uuidAliasResolver}
        @hydrant.connect uuid: 'nsa-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) => @hydrant.close()

          @dispatcher.generateJobs job, (error, @generatedJobs) =>
            setTimeout done, 2000

      it 'should not deliver the sent message to the receiver', ->
        expect(@message).to.not.exist

    context 'subscribed to someone elses received messages', ->
      @timeout 5000
      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'receiver-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'nsa-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        doneTwice = _.after 2, done
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage2'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        client = new RedisNS 'messages', redis.createClient(@redisUri)
        @hydrant = new HydrantManager {client, @uuidAliasResolver}
        @hydrant.connect uuid: 'nsa-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            doneTwice()

          @dispatcher.generateJobs job, (error, @generatedJobs) => doneTwice()

      it 'should deliver the sent message to the receiver', ->
        expect(@message).to.exist

    context 'subscribed to someone elses received messages, but is not authorized', ->
      @timeout 5000
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'receiver-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'spy-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage2'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        client = new RedisNS 'messages', redis.createClient(@redisUri)
        @hydrant = new HydrantManager {client, @uuidAliasResolver}
        @hydrant.connect uuid: 'spy-uuid', (error) =>
          return done(error) if error?
          @hydrant.once 'message', (@message) => @hydrant.close()

          @dispatcher.generateJobs job, (error, @generatedJobs) =>
            setTimeout done, 2000

      it 'should not deliver the sent message to the receiver', ->
        expect(@message).to.not.exist
