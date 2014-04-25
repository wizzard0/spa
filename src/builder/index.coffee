fs = require('fs')
walk = require('fs-walk')
path = require('path')
detective = require('detective')
crypto = require('crypto')
_  = require('underscore')
_.string =  require('underscore.string')
_.mixin(_.string.exports())

preg_quote = (str, delimiter) ->
    return (str + '')
        .replace(new RegExp('[.\\\\+*?\\[\\^\\]${}=!<>|:\\' + (delimiter || '') + '-]', 'g'), '\\$&')

globStringToRegex = (str) ->
    return new RegExp(
        preg_quote(str)
            .replace(/\\\*\\\*/g, '[^/]*(?:/[^/]+)*')
            .replace(/\\\*/g, '[^/]*')
            .replace(/\\\?/g, '[^/]')
        , 'm')

class CyclicDependenciesError extends Error
    constructor: (_loop) ->
        @_loop = _loop
        @name = @constructor.name
        @message = "Can't sort modules. Loop found: \n#{@_loop}"

class UnresolvedDependencyError extends Error
    constructor: (path, alias) ->
        @path = path
        @alias = alias
        @name = @constructor.name
        @message = "Can't resolve dependency `#{@alias}` "+
                   "inside module `#{@path}`"

class ExternalDependencyError extends Error
    constructor: (path, alias, dep) ->
        @path = path
        @alias = alias
        @dep = dep
        @name = @constructor.name
        @message = "Module at path `#{dep}` is required from `#{path}` " +
                   "as `#{alias}`, but it cant be found inside building scope."

class Loop
    constructor: (path, alias) ->
        @_parts = [[path, alias]]
    prepend: (path, alias) ->
        @_parts.unshift([path, alias])
        return this
    toString: ->
        return "" if @_parts.length == 0
        p = @_parts.concat([@_parts[0]])
        return (for i in [0..@_parts.length-1] 
            "#{p[i][0]} --[#{p[i][1]}]--> #{p[i+1][0]}" 
            ).join("\n")
            
class Builder
    constructor: (options) ->
        @root = options.root
        @extensions = options.extensions
        @excludes = _(options.excludes).map(globStringToRegex)
        @paths = options.paths
        @hosting = for pattern, template of options.hosting
            pattern: globStringToRegex(pattern)
            template: template
        @manifest = options.manifest
        @_clear()

    filter: (filepath) ->
        return false unless _(@extensions).any (ext) -> 
            path.extname(filepath) is ext
        return not _(@excludes).any (pattern) -> 
            pattern.test(filepath)

    _clear: ->
        @_modules = []
        @_by_path = {}
        @_by_id = {}

    _enlist: (root) ->
        walk.filesSync root, (basedir, filename, stat) =>
            filepath = path.join(basedir, filename)
            relative = '/' + path.relative(root, filepath)
                .split(path.sep).join('/')

            return unless @filter(relative)

            module =
                path: filepath
                relative: relative

            @_by_path[filepath] = module
            @_modules.push(module)
        return

    _set_ids: ->
        for module in @_modules
            ext = path.extname(module.path)
            root = path.dirname(module.path)
            id = path.basename(module.path, ext)

            if id is "index"
                id = path.basename(root)
                root = path.dirname(root)

            while id of @_by_id
                id = path.basename(root) + "|" + id
                root = path.dirname(root)

            @_by_id[id] = module
            module.id = id
        return

    _resolve_to_file: (filepath) ->
        if fs.existsSync(filepath)
            stats = fs.statSync(filepath)
            if stats.isFile()
                return filepath
        return

    _resolve_to_directory: (dirpath) ->
        if fs.existsSync(dirpath)
            stats = fs.statSync(dirpath)
            if stats.isDirectory()
                return @_resolve_to_file(path.join(dirpath, "index.js"))
        return

    _resolve: (module, dep) ->
        for alias, prefix of @paths
            if _(dep).startsWith(alias)
                dep = dep.replace(alias, prefix)
                break

        if _(dep).startsWith("/")
            dep = path.join(@root, dep)
        else if _(dep).startsWith("./") or _(dep).startsWith("../")
            basedir = path.dirname(module.path)
            dep = path.resolve(basedir, dep)

        return @_resolve_to_file(dep) ? 
               @_resolve_to_file(dep + ".js") ? 
               @_resolve_to_directory(dep)

    _analyze: (module) ->
        source = fs.readFileSync(module.path)
        module.md5 = crypto.createHash('md5').update(source).digest('hex');
        module.size = source.length
        module.deps_paths = {}

        for dep in detective(source)
            resolved = @_resolve(module, dep)
            unless resolved?
                throw new UnresolvedDependencyError(module.relative, dep)
            module.deps_paths[dep] = resolved
    
    _find_loop: (candidates) ->
        for candidate in candidates
            walked = []
            _go_deep = (current) =>
                module = @_by_path[current]
                relative = module.relative
                deps = module.deps_paths
                for alias, dep of deps
                    continue unless dep in candidates
                    continue if dep in walked
                    return new Loop(relative, alias) if dep is candidate
                    walked.push(dep)
                    deep = _go_deep(dep)
                    walked.pop()
                    return deep.prepend(relative, alias) if deep?
            has_loop = _go_deep(candidate)
            return has_loop if has_loop?

    _sort: ->
        left = (module.path for module in @_modules)
        order = []
        while left.length > 0
            use = []
            for mpath in left
                deps = @_by_path[mpath].deps_paths
                use.push(mpath) unless _(deps).any((dep) -> dep not in order)
            if use.length == 0
                throw new CyclicDependenciesError(@_find_loop(left))
            order.push(use...)
            left = left.filter((mpath) -> mpath not in use)
        @_modules = (@_by_path[mpath] for mpath in order)

    _link: ->
        for module in @_modules
            module.deps_ids = {}
            for dep, resolved of module.deps_paths
                if @_by_path[resolved]?
                    module.deps_ids[dep] = @_by_path[resolved].id
                else
                    throw new ExternalDependencyError(module.relative, dep, resolved)

    _host: (module) ->
        for rule in @hosting
            continue unless rule.pattern.test(module.relative)
            module.url = module.relative.replace(rule.pattern, rule.template)
            break
        return

    _write_manifest: ->
        data = for module in @_modules
            id: module.id
            url: module.url
            md5: module.md5
            size: module.size
            deps: module.deps_ids

        console.log(data)

        filename = path.resolve(@root, @manifest)
        content = JSON.stringify(data)
        fs.writeFileSync(filename, content)

    build: () ->
        @_enlist(@root)
        @_set_ids()
        for module in @_modules
            @_analyze(module)
        @_link()
        @_sort()
        for module in @_modules
            @_host(module)
        @_write_manifest()
        return

module.exports = Builder

builder = new Builder
    root: path.resolve(process.cwd(), "./tests/building/") 
    extensions: [".js"]
    excludes: [
        "/node_modules/**"
        #"/module1/**"
        ]
    paths:
        "a1": "/module1/a"
    hosting:
        "/(**/*.js)": "http://127.0.0.1:8010/$1"
    manifest: "manifest.json"

builder.build()
