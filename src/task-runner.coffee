_          = require 'lodash'
debug      = require('debug')('meshblu-core-dispatcher:task-runner')
moment     = require 'moment'

class TaskRunner
  constructor: (options={}) ->
    {
      @config
      @request
      @datastoreFactory
      @pepper
      @cacheFactory
      @uuidAliasResolver
      @meshbluConfig
      @forwardEventDevices
      @jobManager
      @logJobs
      @indexName
      @client
      @workerName
      @privateKey
    } = options
    @todaySuffix = moment.utc().format('YYYY-MM-DD')


  @TASKS =
    'meshblu-core-task-black-list-token'                   : require('meshblu-core-task-black-list-token')
    'meshblu-core-task-cache-token'                        : require('meshblu-core-task-cache-token')
    'meshblu-core-task-check-configure-whitelist'          : require('meshblu-core-task-check-configure-whitelist')
    'meshblu-core-task-check-configure-as-whitelist'       : require('meshblu-core-task-check-configure-as-whitelist')
    'meshblu-core-task-check-discover-whitelist'           : require('meshblu-core-task-check-discover-whitelist')
    'meshblu-core-task-check-discover-as-whitelist'        : require('meshblu-core-task-check-discover-as-whitelist')
    'meshblu-core-task-check-forwarded-for'                : require('meshblu-core-task-check-forwarded-for')
    'meshblu-core-task-check-receive-whitelist'            : require('meshblu-core-task-check-receive-whitelist')
    'meshblu-core-task-check-receive-as-whitelist'         : require('meshblu-core-task-check-receive-as-whitelist')
    'meshblu-core-task-check-send-whitelist'               : require('meshblu-core-task-check-send-whitelist')
    'meshblu-core-task-check-send-as-whitelist'            : require('meshblu-core-task-check-send-as-whitelist')
    'meshblu-core-task-check-token'                        : require('meshblu-core-task-check-token')
    'meshblu-core-task-check-token-black-list'             : require('meshblu-core-task-check-token-black-list')
    'meshblu-core-task-check-token-cache'                  : require('meshblu-core-task-check-token-cache')
    'meshblu-core-task-deliver-webhook'                    : require('meshblu-core-task-deliver-webhook')
    'meshblu-core-task-enqueue-deprecated-webhooks'        : require('meshblu-core-task-enqueue-deprecated-webhooks')
    'meshblu-core-task-enqueue-webhooks'                   : require('meshblu-core-task-enqueue-webhooks')
    'meshblu-core-task-forbidden'                          : require('meshblu-core-task-forbidden')
    'meshblu-core-task-get-device'                         : require('meshblu-core-task-get-device')
    'meshblu-core-task-get-device-public-key'              : require('meshblu-core-task-get-device-public-key')
    'meshblu-core-task-search-device'                      : require('meshblu-core-task-search-device')
    'meshblu-core-task-get-subscriptions'                  : require('meshblu-core-task-get-subscriptions')
    'meshblu-core-task-no-content'                         : require('meshblu-core-task-no-content')
    'meshblu-core-task-remove-token-cache'                 : require('meshblu-core-task-remove-token-cache')
    'meshblu-core-task-send-message'                       : require('meshblu-core-task-send-message')
    'meshblu-core-task-update-device'                      : require('meshblu-core-task-update-device')
    'meshblu-core-task-protect-your-as'                    : require('meshblu-core-task-protect-your-as')
    'meshblu-core-task-publish-message'                    : require('meshblu-core-task-publish-message')
    'meshblu-core-task-publish-deprecated-subscriptions'   : require('meshblu-core-task-publish-deprecated-subscriptions')
    'meshblu-core-task-publish-subscriptions'              : require('meshblu-core-task-publish-subscriptions')
    'meshblu-core-task-revoke-token-by-query'              : require('meshblu-core-task-revoke-token-by-query')

  run: (callback) =>
    @_doTask @config.start, callback

  _doTask: (name, callback) =>
    startTime = Date.now()
    taskConfig = @config.tasks[name]
    return callback new Error "Task Definition '#{name}' not found" unless taskConfig?

    taskName = taskConfig.task
    Task = TaskRunner.TASKS[taskName]
    return callback new Error "Task Definition '#{name}' missing task class" unless Task?

    debug '_doTask', taskName

    datastore = @datastoreFactory.build taskConfig.datastoreCollection if taskConfig.datastoreCollection?
    cache  = @cacheFactory.build taskConfig.cacheNamespace if taskConfig.cacheNamespace?

    task = new Task {
      @uuidAliasResolver
      datastore
      cache
      @pepper
      @meshbluConfig
      @forwardEventDevices
      @jobManager
      @privateKey
    }
    task.do @request, (error, response) =>
      return callback error if error?
      debug taskName, response
      {metadata} = response

      codeStr = metadata?.code?.toString()
      nextTask = taskConfig.on?[codeStr]
      @logTask {startTime, @request, response, taskName}, =>
        return callback null, response unless nextTask?
        @_doTask nextTask, callback

  logTask: (options, callback) =>
    options.type = 'task'
    @_log options, callback

  _log: ({startTime, request, response, type, taskName}, callback) =>
    return callback() unless @logJobs
    requestMetadata = _.cloneDeep request.metadata
    delete requestMetadata.auth?.token
    requestMetadata.workerName = @workerName
    requestMetadata.taskName = taskName

    job =
      index: "#{@indexName}-#{@todaySuffix}"
      type: type
      body:
        elapsedTime: Date.now() - startTime
        date: Date.now()
        request:
          metadata: requestMetadata
        response: _.pick(response, 'metadata')

    @client.lpush 'job-log', JSON.stringify(job), (error, result) =>
      console.error 'Dispatcher.log', {error} if error?
      callback error

module.exports = TaskRunner
