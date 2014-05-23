selenium = require('selenium-standalone')
webdriverjs = require('webdriverjs')

mock = require("mock-fs")
fs = require("fs")
path = require("path")
yaml = require("js-yaml")
chai = require('chai')
expect = chai.expect
assert = chai.assert
connect = require("connect")
spa = require("../lib")
utils = require("./utils")

DELAY = 200

describe.skip "webdriverjs", ->
    @timeout(20000)

    before (done) ->
        @server = selenium()

        @app = connect()
            .use connect.logger()
            .use connect.static("/", redirect: true)
        connect.createServer(@app).listen(3333)

        @client = webdriverjs.remote
            desiredCapabilities:
                browserName: 'firefox'
        @client.init(done)

    after (done) ->
        @client.end =>
            @server.kill()
            @app.removeAllListeners()
            done()

    beforeEach ->
        @old_cwd = process.cwd()
        process.chdir("/")

    afterEach ->
        mock.restore()
        process.chdir(@old_cwd)

    describe 'Simple update', ->

        it 'should update single file only after manifest regenerated', (done) ->
            @client
                .call ->
                    system = yaml.safeLoad("""
                        app:
                            a.js: |
                                var loader = require("loader");
                                loader.onApplicationReady = function() {
                                    document.title = "version_1";
                                    loader.checkUpdate();
                                };
                                loader.onUpdateCompletted = function(event) {
                                    setTimeout(location.reload.bind(location), 0)
                                    return true
                                };
                            spa.yaml: |
                                root: "./"
                                manifest: "./manifest.json"
                                index: "./index.html"
                                assets:
                                    index_template: /assets/index.tmpl
                                    appcache_template: /assets/appcache.tmpl
                                    loader: /assets/loader.js
                                    md5: /assets/md5.js
                                    fake_app: /assets/fake/app.js
                                    fake_manifest: /assets/fake/manifest.json
                                hosting:
                                    "/a.js": "/app/a.js"
                        """)
                    utils.mount(system, "assets", path.resolve(__dirname, "../lib/assets"))
                    mock(system)
                    spa.Builder.from_config("/app/spa.yaml").build()
                .url('http://127.0.0.1:3333/app/index.html')
                .pause(DELAY)
                .getTitle (err, source) ->
                    expect(err).to.be.null
                    expect(source).to.be.equal("version_1")
                .url('http://127.0.0.1:3333/app/index.html')
                .pause(DELAY)
                .getTitle (err, source) ->
                    expect(err).to.be.null
                    expect(source).to.be.equal("version_1")
                .call ->
                    content = """
                        var loader = require("loader");
                        loader.onApplicationReady = function() {
                            document.title = "version_2";
                        };
                        """
                    fs.writeFileSync("/app/a.js", content)
                .url('http://127.0.0.1:3333/app/index.html')
                .pause(DELAY)
                .getTitle (err, source) ->
                    expect(err).to.be.null
                    expect(source).to.be.equal("version_1")
                .call ->
                    spa.Builder.from_config("/app/spa.yaml").build()
                .url('http://127.0.0.1:3333/app/index.html')
                .pause(DELAY)
                .getTitle (err, source) ->
                    expect(err).to.be.null
                    expect(source).to.be.equal("version_2")
                .call(done)