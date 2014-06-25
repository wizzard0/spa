fs = require("fs")
path = require("path")
coffee = require("coffee-script")
uglify = require("uglify-js")
mkdirpSync = require('mkdirp').sync
sass = require('node-sass')
walker = require('fs-walk-glob-rules')
{exec} = require 'child_process'

minify = (source) -> 
    ast = uglify.parse(source)
    ast.figure_out_scope()

    compressor = uglify.Compressor
        sequences     : true
        properties    : true
        dead_code     : true
        drop_debugger : true
        unsafe        : false
        conditionals  : true
        comparisons   : true
        evaluate      : true
        booleans      : true
        loops         : true
        unused        : true
        hoist_funs    : true
        hoist_vars    : false
        if_return     : true
        join_vars     : true
        cascade       : true
        side_effects  : true
        warnings      : false
        negate_iife   : false
        global_defs   : {}   

    compressed = ast.transform(compressor)
    minified = compressed.print_to_string()

    return minified

minify_more = (source) ->
    ast = uglify.parse(source)
    ast.figure_out_scope()
    ast.compute_char_frequency()
    ast.mangle_names()
    
    compressor = uglify.Compressor
        warnings      : false
        negate_iife   : false
        global_defs: {}

    compressed = ast.transform(compressor)
    minified = compressed.print_to_string
        bracketize    : true
        comments      : /License/

    return minified

write_file = (relative, data) ->
    outpath = path.join(".", relative) 
    mkdirpSync(path.dirname(outpath))
    fs.writeFileSync(outpath, data)

transform = (source, destination, func, excludes) -> 
    rules = {}
    rules[source] = destination
    walked = walker.walkSync
        root: "."
        rules: rules
        excludes: [
            "./node_modules/**",
            "./.git/**"
        ]

    for data in walked
        content = fs.readFileSync(data.source, encoding: "utf8")
        result = func(data.source, data.result, content, data.match)
        if destination? and result?
            write_file(data.result, result)

task "compile-builder", "compile builder coffee source into javascript", ->
    console.log("Compiling builder")
    transform "./src/builder/(**/*).coffee", "./lib/$1.js", (input, output, data) ->
        console.log("Compiling %s --> %s", input, output)
        return coffee.compile(data, bare: true)

task "compile-loader", "compile loader coffee source into javascript", ->
    console.log("Compiling loader")
    transform "./src/loader/(**/*).coffee", "./lib/assets/$1.js", (input, output, data) ->
        console.log("Compiling %s --> Minifying --> %s", input, output)
        result = coffee.compile(data, bare: true)
        return minify(result)

    parts = [ # order of this files is important
        "./src/bootstrap/ui.coffee",
        "./src/bootstrap/app.coffee",
    ]
    out = []

    for part in parts
        transform part, null, (input, _, data) ->
            console.log("Compiling %s -->", input)
            result = coffee.compile(data, bare: true)
            out.push(result)
            return

    bootstrap_path = "./lib/assets/bootstrap.js"
    bootstrap_data = out.join("")

    console.log("    --> Combining %s", bootstrap_path)
    write_file(bootstrap_path, bootstrap_data)

task "populate-assets", "prepare assets to be used by builder", ->

    transform "./src/cryptojs/encoder.coffee", null, (input, _, data) ->
        encoder = coffee.compile(data, bare: true)
        console.log("Compiling %s -->", input)

        transform "./bower_components/cryptojslib/rollups/(md5|sha1|sha224|sha256|sha3|sha384|sha512|ripemd160).js", "./lib/assets/hash/$1.js", (input, output, data, match) ->

            console.log("    Combining %s --> %s", input, output)
            hash_name = match[1]
            return minify_more("""
                (function() {
                    #{data};
                    var ALGO = "#{hash_name.toUpperCase()}";
                    return #{encoder};
                })();""")

    transform "./bower_components/localforage/dist/(localforage).min.js", "./lib/assets/$1.js", (input, output, data) ->
        console.log("Copying %s --> %s", input, output)
        return data

    transform "./src/builder/index.tmpl", "lib/assets/index.tmpl", (input, output, data) ->
        console.log("Copying %s --> %s", input, output)
        return data

    transform "./src/builder/appcache.tmpl", "lib/assets/appcache.tmpl", (input, output, data) ->
        console.log("Copying %s --> %s", input, output)
        return data

    transform "./src/bootstrap/style.scss", "lib/assets/bootstrap.css", (input, output, data) ->
        console.log("Compiling %s --> %s", input, output)
        sass.renderFile
            file: path.join('.', input)
            outputStyle: 'compressed'
            outFile: output
            success: (x) -> console.log("Success", x)
            error: console.log.bind(console)
        return

task "test", "run unittests", ->
    cmd = ["npm", "run", "test:unit"].join(" ")
    console.log(cmd)
    exec cmd, (err, stdout, stderr) ->
        throw err if err
        console.log stdout + stderr

task "build", "compile all coffeescript files to javascript", ->
    invoke 'compile-builder'
    invoke 'compile-loader'
    invoke 'populate-assets'

task "sbuild", "build routine for sublime", ->
    invoke 'build'
    invoke 'test'

