class AbstractMethodError extends Error
    constructor: ->
        @name = "AbstractMethodError"
        @message = "Calling abstract method detected."

class UndeclaredRequireError extends Error
    constructor: (@self_name, @require_name) ->
        @name = "UndeclaredRequireError"
        @message = "Found unreserved attempt to require of `#{@require_name}` inside `#{@self_name}`"

class ChangesInWindowError extends Error
    constructor: (@self_name, @props) ->
        @name = "ChangesInWindowError"
        @message = "During `#{@self_name}` loading window object was polluted with: #{props}"

class NoSourceError extends Error
    constructor: (@url) ->
        @name = "NoSourceError"
        @message = "Module #{@url} source was not found in local database. Probably it was not loaded."

class ExportsViolationError extends Error
    constructor: (@self_name) ->
        @name = "ExportsViolationError"
        @message = "Modules `#{@self_name}` overrides own exports by replacing. `exports` != `module.exports`"

class ReturnPollutionError extends Error 
    constructor: (@self_name, @props) ->
        @name = "ReturnPollutionError"
        @message = "Code of `#{@self_name}` contains `return` statement in module scope."

class ThisPollutionError extends Error 
    constructor: (@self_name, @props) ->
        @name = "ThisPollutionError"
        @message = "Code of `#{@self_name}` trying to modify host object."

class AMDReturnsNothingError extends Error 
    constructor: (@self_name) ->
        @name = "AMDReturnsNothingError"
        @message = "AMD module `#{@self_name}` returns nothing. Should return empty object!"

waitAll = (array, reduce, map) ->
    items = array.concat()
    results = []
    received = []
    counter = 0
    items.forEach (item, index) ->
        map item, (result) ->
            counter++
            results[index] = result
            received[index] = true
            for i in [0..items.length-1]
                return if !received[i]
            return reduce(results)
        return
    return

hasBOM = (data) ->
    return false if data.length < 3
    return false unless data[0] is 0xef
    return false unless data[1] is 0xbb
    return false unless data[2] is 0xbf
    return true

decodeUtf8 = (arrayBuffer) ->
    result = ""
    i = 0
    c = 0
    c1 = 0
    c2 = 0

    data = new Uint8Array(arrayBuffer)

    i = 3 if hasBOM(data)

    while i < data.length
        c = data[i]

        if c < 128
            result += String.fromCharCode(c)
            i++
        else if 191 < c < 224
            if i + 1 >= data.length
                throw "UTF-8 Decode failed. Two byte character was truncated."
            c2 = data[i + 1]
            result += String.fromCharCode( ((c & 31) << 6) | (c2 & 63) )
            i += 2
        else
            if i + 2 >= data.length
                throw "UTF-8 Decode failed. Multi byte character was truncated."
            c2 = data[i + 1]
            c3 = data[i + 2]
            result += String.fromCharCode( ((c & 15) << 12) | ((c2 & 63) << 6) | (c3 & 63) )
            i += 3
    return result

XHR = -> new XMLHttpRequest()

class BasicEvaluator
    constructor: (options) ->
        @id = options.id
        @source = options.source
        @deps = options.dependencies
        @this = {}
        @window = @get_window()
        @errors = []
    render: ->  throw new AbstractMethodError()
    run: ->
        code = @render()
        func = new Function(code)
        result = func.call(this)
        @_check(result)
        return null if @errors.length > 0
        return @_make()
    get_window: -> return __proto__: window
    get_require: -> throw new AbstractMethodError()
    _fail: (reason) ->
        @errors.push(reason)
        throw reason
    _check: (result) -> throw new AbstractMethodError()
    _make: -> throw new AbstractMethodError()

class CJSEvaluator extends BasicEvaluator
    constructor: (options) ->
        super(options)
        @module = {}
        @exports = {}
        @module.exports = @exports
        @require = @get_require()
    render: -> return """
        return (function(module, exports, require, window) { 
            #{@source}; 
        }).call(this.this, this.module, this.exports, this.require, this.window);
        """
    get_require: ->
        require = (name) -> 
            value = @deps[name]
            if not value?
                @_fail(new UndeclaredRequireError(@id, name)) 
            return value
        return require.bind(this);
    _check: (result) ->
        window_keys = Object.keys(@window)
        unless window_keys.length == 0
            throw new ChangesInWindowError(@id, window_keys) 
        unless @exports is @module.exports or Object.keys(@exports).length == 0
            throw new ExportsViolationError(@id) 
        if result?
            throw new ReturnPollutionError(@id, Object.keys(result)) 
        this_keys = Object.keys(@this)
        unless this_keys.length == 0
            throw new ThisPollutionError(@id, this_keys) 
    _make: ->
        return @module.exports

class AMDEvaluator extends BasicEvaluator
    constructor: (options) ->
        super(options)
        @define = @get_define()
    render: -> return """
        return (function(define, window) { 
            #{@source}; 
        }).call(this.this, this.define, this.window);
        """
    get_define: ->
        define = (names, func) ->
            deps = (@deps[name] for name in names)
            @result = func.apply(this.this, deps)
        return define.bind(this);
    _check: (result) ->
        window_keys = Object.keys(@window)
        unless window_keys.length == 0
            throw new ChangesInWindowError(@id, window_keys) 
        if result?
            throw new ReturnPollutionError(@id, Object.keys(result)) 
        this_keys = Object.keys(@this)
        unless this_keys.length == 0
            throw new ThisPollutionError(@id, this_keys)
        unless @result?
            throw new AMDReturnsNothingError(@id)
    _make: ->
        return @result

class PollutionEvaluator extends BasicEvaluator
    render: ->
        names = ["window"]
            .concat(name for name of @deps)
            .join(", ")

        args = ["this.this", "this.window"]
            .concat("this.deps[\"#{name}\"]" for name of @deps)
            .join(", ")

        return """
            return (function(#{names}) {
                #{@source};
            }).call(#{args});
        """
    _check: (result) ->
        if result?
            throw new ReturnPollutionError(@id, Object.keys(result)) 
    get_window: -> 
        result = 
            __proto__: super()
        for name, value of @deps
            result[name] = value
        return __proto__: result
    _make: ->
        result = {}
        for own name, value of @window
            result[name] = value
        for own name, value of @this
            result[name] = value
        return result

class RawEvaluator extends BasicEvaluator
    render: -> return @source
    _check: (result) ->
    get_window: -> return window
    _make: -> return {}

SAFE_CHARS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'

class Loader
    constructor: (options) ->
        @_all_modules = {}

        @_current_manifest = null

        @_update_started = false

        @_modules_to_load = []
        @_new_manifest = null
        @_total_size = 0

        @_evaluators =
            cjs: CJSEvaluator
            amd: AMDEvaluator
            junk: PollutionEvaluator
            raw: RawEvaluator

        @version = options.version
        @prefix = options.prefix
        @hash_name = options.hash_name
        @hash_func = options.hash_func
        @randomize_urls = options.randomize_urls
        @manifest_location = options.manifest_location ? "manifest.json"

        @manifest_key = @prefix + "::manifest"
        localforage.config()

    _prepare_url: (url) ->
        return escape(url) unless @randomize_urls
        result = ''
        for i in [0..16]
            result += SAFE_CHARS[Math.round(Math.random() * (SAFE_CHARS.length - 1))]
        return escape(url) + '?' + result
    
    _parse_manifest: (content) ->
        throw ReferenceError("Manifest was not defined") unless content?
        raw = JSON.parse(content)
        throw TypeError("Invalid manifest format") unless raw instanceof Object
        throw TypeError("Invalid manifest format") unless raw.modules?
        throw TypeError("Invalid manifest version. Got: #{raw.version}. Expected: #{@version}") unless raw.version is @version
        throw TypeError("Invalid manifest hash function. Got: #{raw.hash_func}. Expected: #{@hash_name}") unless raw.hash_func is @hash_name

        manifest = 
            content: content
            modules: raw.modules
            version: raw.version
            hash_func: raw.hash_func
            hash: @hash_func(content)

        return manifest

    get_manifest: ->
        return @_parse_manifest(window.localStorage.getItem(@manifest_key))

    set_manifest: (manifest) ->
        window.localStorage.setItem(@manifest_key, manifest.content)
        return

    make_key: (module) ->
        return @prefix + ":" + module.hash + ":" + module.url

    get_content: (key, cb) -> 
        return localforage.getItem(key, cb)

    set_content: (key, content, cb) ->
        @log("storing", key)
        return localforage.setItem(key, content, cb)

    get_contents_keys: (cb) ->
        localforage.length (length) =>
            c = 0
            buf = []
            receive = (num, key) ->
                c++
                buf[num] = key
                return if c < length
                for key in buf
                    cb(key)
                return
            for i in [0..length-1]
                localforage.key(i, receive.bind(this, i))
        return

    del_content: (key, cb) ->
        @log("removing", key)
        return localforage.removeItem(key, cb)

    log: (args...) -> 
        console.log("LOADER:#{@prefix}", args...)

    log_error: (args...) -> 
        console.error("LOADER:#{@prefix}", args...)

    onNoManifest: ->
    onUpToDate: (event) ->
    onUpdateFound: (event, manifest) -> @startUpdate()
    onUpdateFailed: (event, error)-> 
    onUpdateCompleted: (manifest) -> return true
    onModuleBeginDownload: (module) -> 
    onModuleDownloadFailed: (event, module) -> 
    onModuleDownloadProgress: (event, module) -> 
    onTotalDownloadProgress: (progress) -> 
    onModuleDownloaded: (module) -> 
    onEvaluationStarted: (manifest) -> 
    onEvaluationError: (module, error) -> 
    onModuleEvaluated: (module) -> 
    onApplicationReady: (manifest) -> @checkUpdate()

    emit: (name, args...) ->
        @log(name, args...)
        try
            return this["on" + name](args...)
        catch error
            @log_error(error)

    load: ->
        try
            @_current_manifest = @get_manifest()
        catch error
            @emit("NoManifest")
            return

        @emit("EvaluationStarted", @_current_manifest)
        @log("Current manifest", @_current_manifest.content)
        @evaluate(@_current_manifest.modules)
        @_cleanUp()
        return

    evaluate: (queue) ->
        queue = queue.concat()
        if queue.length is 0
            @emit("ApplicationReady", @_current_manifest)
            return

        module = queue.shift()
        key = @make_key(module)
        @get_content key, (module_source) =>
            unless module_source?
                @emit("EvaluationError", module, new NoSourceError(module.url))
                return

            try
                if module_source instanceof ArrayBuffer
                    module.source = decodeUtf8(module_source)
                else
                    module.source = module_source
            catch error
                @emit("EvaluationError", module, error)
                return

            deps = {}
            for alias, dep of module.deps
                deps[alias] = @_all_modules[dep]
            deps["loader"] = this

            evaluator = new @_evaluators[module.type ? "cjs"]
                id: module.id
                source: module.source
                dependencies: deps

            try
                namespace = evaluator.run()
            catch error
                @emit("EvaluationError", module, error)
                return

            @_all_modules[module.id] = namespace
            module.namespace = namespace

            @emit("ModuleEvaluated", module)

            @evaluate(queue)

    checkUpdate: () ->
        return if @_update_started
        @log("Checking for update...")
        manifest_request = XHR()
        manifest_request.open("GET", @_prepare_url(@manifest_location), true)
        manifest_request.overrideMimeType("application/json; charset=utf-8")
        manifest_request.onload = (event) =>
            if event.target.status is 404
                @emit("UpdateFailed", event, null)
                return
            try 
                @_new_manifest = @_parse_manifest(event.target.response)
            catch error
                @emit("UpdateFailed", event, error)
                return

            @log("New manifest", @_new_manifest.content)
            if @_current_manifest?
                if @_current_manifest.hash == @_new_manifest.hash
                    @emit("UpToDate", @_current_manifest)
                    return

            @emit("UpdateFound", event, @_new_manifest)

        manifest_request.onerror = (event) =>
            @emit("UpdateFailed", event, null)
        manifest_request.onabort = (event) =>
            @emit("UpdateFailed", event, null)

        manifest_request.send()
        return

    startUpdate: ->
        @log("Starting update...")
        @_update_started = true
        for module in @_new_manifest.modules
            module.loaded = 0
        @_modules_to_load = @_new_manifest.modules.concat()
        for module in @_modules_to_load.splice(0, 4)
            @_updateModule(module)
        return

    _updateModule: (module) ->
        key = @make_key(module)
        @get_content key, (module_source) =>
            if module_source?
                module.source = module_source
                @_reportTotalProgress()
                @_checkAllUpdated()
            else
                @_downloadModule(module)
            return
        return

    _reportTotalProgress: ->
        loaded_size = 0
        total_size = 0
        loaded_count = 0
        total_count = 0
        for module in @_new_manifest.modules
            total_size += module.size
            loaded_size += module.loaded
            total_count++
            if module.source?
                loaded_count++
        progress = 
            loaded_count: loaded_count
            total_count: total_count
            loaded_size: loaded_size
            total_size: total_size
        @emit("TotalDownloadProgress", progress)

    _downloadModule: (module) ->
        @emit("ModuleBeginDownload", module)
        module_request = XHR()
        module_request.open("GET", @_prepare_url(module.url), true)
        module_request.responseType = "arraybuffer"
        module_request.onload = (event) =>
            module_source = event.target.response
            if @hash_func(module_source) != module.hash
                @emit("ModuleDownloadFailed", event, module)
                return
            @set_content @make_key(module), module_source, =>
                module.source = module_source
                module.loaded = module.size
                @emit("ModuleDownloaded", module)
                @_reportTotalProgress()
                @_checkAllUpdated()
        module_request.onprogress = (event) =>
            module.loaded = event.loaded
            @emit("ModuleDownloadProgress", event, module)
            @_reportTotalProgress()
        module_request.onerror = (event) =>
            @emit("ModuleDownloadFailed", event, module)
        module_request.onabort = (event) =>
            @emit("ModuleDownloadFailed", event, module)
        module_request.send()
        return

    _checkAllUpdated: ->
        next = @_modules_to_load.shift()
        if next?
            @_updateModule(next)
            return

        for module in @_new_manifest.modules
            return unless module.source?

        if @emit("UpdateCompleted", @_new_manifest)
            @set_manifest(@_new_manifest)
            @_current_manifest = @_new_manifest
            @_new_manifest = null
        @_update_started = false
        return

    _cleanUp: ->
        useful = (@make_key(module) for module in @_current_manifest.modules)
        useful.push(@manifest_key)
        @get_contents_keys (key) =>
            return unless key? # wierd error
            return unless key.indexOf(@prefix) is 0
            return if key in useful
            @del_content(key)
            return
        return
