path = require("path")
fs = require("fs")
Builder = require("./").Builder

exists = (filepath) ->
    console.log("Trying to find #{filepath}")
    return unless fs.existsSync(filepath)
    stats = fs.statSync(filepath)
    return unless stats.isFile()
    return filepath


get_config_path = (arg) ->
    cwd = process.cwd()
    return exists(path.resolve(cwd, arg)) if arg?
    return exists(path.join(cwd, "spa.json")) ?
           exists(path.join(cwd, "spa.yaml")) ?
           exists(path.join(cwd, "spa.yml"))

opts = require('optimist')
    .usage('Usage: $0 <build-config-file>')
    .options
        config:
            describe: "path to build config file"
        help:
            boolean: true
        debug: 
            boolean: true

argv = opts.parse(process.argv)

if argv.help
    console.log(opts.help())
    process.exit()

builder = Builder.from_config(get_config_path(argv.config))
try
    builder.build()
catch error
    console.log(error.toString())
