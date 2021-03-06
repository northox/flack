
#
# specifying flack
#
# Tue Oct  4 05:45:10 JST 2016
#

require 'spec_helper'


describe '/message' do

  before :each do

    @app = Flack::App.new('envs/test/etc/conf.json', start: false)
    @app.unit.conf['unit'] = 'u'
    #@app.unit.hook('journal', Flor::Journal)
    @app.unit.storage.delete_tables
    @app.unit.storage.migrate
    @app.unit.start
  end

  after :each do

    @app.unit.shutdown
  end

  describe 'POST /message' do

    context 'any msg' do

      it 'goes 400 if the point is missing' do

        msg = {}

        r = @app.call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(400)
        expect(r[1]['Content-Type']).to eq('application/json')

        j = JSON.parse(r[2].join)

        expect(j['error']).to eq('missing msg point')
        expect(j['_links']['self']['method']).to eq('POST')
      end

      it 'goes 400 if the point is unknown' do

        msg = { point: 'flip' }

        r = @app.call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(400)
        expect(r[1]['Content-Type']).to eq('application/json')

        j = JSON.parse(r[2].join)

        expect(j['error']).to eq('bad msg point "flip"')
      end
    end

    context 'a launch msg' do

      it 'goes 400 if the domain is missing' do

        msg = { point: 'launch' }

        r = @app.call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(400)
        expect(r[1]['Content-Type']).to eq('application/json')

        j = JSON.parse(r[2].join)

        expect(j['error']).to eq('missing domain')
      end

      it 'goes 400 if the tree is missing' do

        msg = { point: 'launch', domain: 'org.example' }

        r = @app.call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(400)
        expect(r[1]['Content-Type']).to eq('application/json')

        j = JSON.parse(r[2].join)

        expect(j['error']).to eq('missing "tree" or "name" in launch msg')
      end

      it 'launches and goes 201' do

        t = Flor::Lang.parse("stall _", "#{__FILE__}:#{__LINE__}")

        msg = { point: 'launch', domain: 'org.example', tree: t }

        r = @app.call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(201)
        expect(r[1]['Content-Type']).to eq('application/json')
        expect(r[1]['Location']).to match(/\A\/executions\/org\.example-u-2/)

        j = JSON.parse(r[2].join)

        expect(j['_status']).to eq(201)
        expect(j['_status_text']).to eq('Created')

        expect(
          j['_location']
        ).to match(/\A\/executions\/org\.example-u-2/)

        expect(
          j['_links']['flack:forms/message-created']['href']
        ).to match(/\A\/executions\/org\.example-u-2/)

        expect(j['exid']).to match(/\Aorg\.example-u-2/)

        sleep 0.3

        es = @app.unit.executions.all

        expect(es.collect(&:exid)).to eq([ j['exid'] ])
        expect(es.collect(&:domain)).to eq(%w[ org.example ])
        expect(es.collect(&:status)).to eq(%w[ active ])
      end
    end

    context 'a cancel msg' do

      it 'goes 400 if the exid is missing' do

        msg = { point: 'cancel' }

        r = @app
          .call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(400)

        j = JSON.parse(r[2].join)

        expect(j['_status']).to eq(400)
        expect(j['_status_text']).to eq('Bad Request')

        expect(j['error']).to eq('missing exid')
      end

      it 'goes 404 if the execution does not exist' do

        msg = {
          point: 'cancel', exid: 'org.example-u-20161007.2140.gulisufebu' }

        r = @app
          .call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(404)

        j = JSON.parse(r[2].join)

        expect(j['_status']).to eq(404)
        expect(j['_status_text']).to eq('Not Found')

        expect(j['error']).to eq('missing execution')
      end

      it 'goes 404 if the execution node does not exist' do

        r = @app.unit
          .launch('stall _', domain: 'org.example', wait: '0 execute')

        exid = r['exid']

        msg = { point: 'cancel', exid: exid, nid: '0_1' }

        sleep 0.4 # wait for the execution to actually exist

        r = @app
          .call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(404)

        j = JSON.parse(r[2].join)

        expect(j['_status']).to eq(404)
        expect(j['_status_text']).to eq('Not Found')

        expect(j['error']).to eq('missing execution node')
      end

      it 'cancels at node 0 by default and goes 202' do

        r = @app.unit
          .launch('stall _', domain: 'org.example', wait: '0 execute')

        sleep 0.3 # skip a beat

        exid = r['exid']

        msg = { point: 'cancel', exid: exid }

        r = @app
          .call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(202)
        expect(r[1]['Location']).to eq('/executions/' + exid)

        j = JSON.parse(r[2].join)

        expect(j['_status']).to eq(202)
        expect(j['_status_text']).to eq('Accepted')

        sleep 0.5

        exes = @app.unit.executions.all

        expect(exes.size).to eq(1)
        expect(exes.first.exid).to eq(exid)
        expect(exes.first.status).to eq('terminated')
      end

      it 'cancels at a given nid and goes 202' do

        r = @app.unit
          .launch(
            %{
              sequence
                stall _
                stall _
            },
            domain: 'org.example',
            wait: '0_0 execute')

        exid = r['exid']

        sleep 0.3 # skip a beat

        msg = { point: 'cancel', exid: exid, nid: '0_0' }

        r = @app
          .call(make_env(method: 'POST', path: '/message', body: msg))

        expect(r[0]).to eq(202)

        sleep 1.0

        exes = @app.unit.executions.all

        expect(exes.size).to eq(1)
        expect(exes.first.exid).to eq(exid)
        expect(exes.first.status).to eq('active')

        expect(exes.first.nodes.keys).to eq(%w[ 0 0_1 ])
      end
    end
  end
end

