Host = require './host'
RemoteFile = require './remote-file'

async = require 'async'
filesize = require 'file-size'
moment = require 'moment'
ftp = require 'ftp'

module.exports =
  class FtpHost extends Host
    constructor: (@hostname, @directory, @username, @port, @password) ->
      super

    createRemoteFileFromListObj: (path, item) ->
      remoteFile = new RemoteFile((path + item.name), false, false, filesize(item.size).human(), null, null)

      if item.type == "d"
        remoteFile.isDir = true
      else if item.type == "-"
        remoteFile.isFile = true
      else if item.type == 'l'
        # this is really a symlink but i add it as a file anyway
        remoteFile.isFile = true

      if item.rights?
        remoteFile.permissions = (@convertRWXToNumber(item.rights.user) + @convertRWXToNumber(item.rights.group) + @convertRWXToNumber(item.rights.other))

      if item.date?
        remoteFile.lastModified = moment(item.date).format("HH:MM DD/MM/YYYY")

      return remoteFile

    convertRWXToNumber: (str) ->
      toreturn = 0
      for i in str
        if i == 'r'
          toreturn += 4
        else if i == 'w'
          toreturn += 2
        else if i == 'x'
          toreturn += 1
      return toreturn.toString()


    ####################
    # Overridden methods
    getConnectionString: ->
      return {
        host: @hostname,
        port: @port,
        user: @username,
        password: @password
      }

    connect: (callback) ->
      async.waterfall([
        (callback) =>
          @connection = new ftp()
          @connection.on 'error', (err) =>
            @connection.end()
            callback(err)
          @connection.on 'ready', () ->
            callback(null)
          @connection.connect(@getConnectionString())
        ], (err, result) ->
          callback(err, result)
        )

    getFilesMetadata: (path, callback) ->
      async.waterfall([
        (callback) =>
          @connection.list(path, callback)
        (files, callback) =>
          async.map(files, ((item, callback) => callback(null, @createRemoteFileFromListObj(path, item))), callback)
        (objects, callback) =>
          if atom.config.get 'remote-edit.showHiddenFiles'
            callback(null, objects)
          else
            async.filter(objects, ((item, callback) -> item.isHidden(callback)), ((result) => callback(null, result)))
        ], (err, result) =>
          return callback(err, (result.sort (a, b) => return if a.name.toLowerCase() >= b.name.toLowerCase() then 1 else -1))
        )

    getFileData: (file, callback) ->
      @connection.get(file.path, (err, stream) ->
        stream.once('data', (chunk) ->
          return callback(null, chunk.toString('utf8'))
        )
      )
