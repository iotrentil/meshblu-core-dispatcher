commander   = require 'commander'
async       = require 'async'
redis       = require 'redis'
redisMock   = require 'redis-js'
packageJSON = require './package.json'
Dispatcher  = require './src/dispatcher'

class Command
  parseOptions: =>
    commander
      .version packageJSON.version
      .option '-n, --namespace <meshblu>', 'request/response queue namespace.', 'meshblu'
      .option '-s, --single-run', 'perform only one job.'
      .option '-t, --timeout <n>', 'seconds to wait for a next job.', parseInt, 30
      .option '-a, --all', 'run all workers in process'
      .parse process.argv

    {@namespace,@singleRun,@timeout,@all} = commander
    @redisUri = process.env.REDIS_URI

    if @all
      @localHandlers  = ['authenticate']
      @remoteHandlers = []
    else
      @localHandlers  = []
      @remoteHandlers = ['authenticate']

  run: =>
    @parseOptions()

    dispatcher = new Dispatcher
      namespace: @namespace
      timeout:   @timeout
      redisUri:  @redisUri
      jobHandlers: @assembleJobHandlers()

    return dispatcher.work(@panic) if @singleRun
    async.forever dispatcher.dispatch, @panic

  assembleJobHandlers: =>
    @localClient = redisMock.createClient()
    @remoteClient = redis.createClient @redisUri

    jobAssembler = new JobAssembler
      timeout: @timeout
      localClient: @localClient
      remoteClient: @remoteClient
      localHandlers: @localHandlers
      remoteHandlers: @remoteHandlers

    jobHandlers = jobAssembler.assemble()

  panic: (error) =>
    console.error error.stack
    process.exit 1

command = new Command()
command.run()
