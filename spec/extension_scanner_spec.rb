require 'spec_helper'

describe ExtensionScanner do

  let(:target_uri) { 'http://localhost' }
  let(:data_file) { 'data/modules.json' }
  let(:opts_user_agent) { 'Mozilla/5.0 (Windows NT 6.3; rv:36.0) Gecko/20100101 Firefox/36.0' }
  let(:opts_threads) { 20 }
  let(:opts_follow_redirection) { nil }
  let(:opts_basic_auth) { nil }
  let(:opts_proxy) { nil }
  let(:opts_proxy_auth) { nil }

  let(:typhoeus_code) { 200 }
  let(:typhoeus_body) { '' }
  let(:typhoeus_headers) { { 'Content-Type' => 'text/html; charset=utf-8' } }

  before :each do
    @scanner = ExtensionScanner.new(target_uri, data_file, {
      :user_agent => opts_user_agent,
      :threads => opts_threads,
      :follow_redirection => opts_follow_redirection,
      :basic_auth => opts_basic_auth,
      :proxy => opts_proxy,
      :proxy_auth => opts_proxy_auth
    })

    Typhoeus.stub(/.*/) do
      Typhoeus::Response.new(code: typhoeus_code, body: typhoeus_body, headers: typhoeus_headers)
    end
  end

  describe '#new' do
    it 'takes three parameters and returns a ExtensionScanner object' do
      expect(@scanner).to be_an_instance_of ExtensionScanner
    end
  end

  describe '#possible_paths' do
    it 'returns nil' do
      expect(@scanner.possible_paths('foo')).to be_nil
    end
  end

  describe '#data_file_json' do
    it 'returns an array of extensions from the data file' do
      expect(@scanner.data_file_json).to be_an_instance_of Array
    end
  end

  describe '#queue_requests' do
    context 'when passed a valid path index' do
      it 'queues a request to be made by hydra' do
        allow(@scanner).to receive(:possible_paths) { ['/foo', '/bar'] }
        @scanner.queue_requests('foo', 0)
        @scanner.queue_requests('bar', 1)
        expect(@scanner.hydra.queued_requests.length).to eq 2
      end
    end

    context 'when passed an invalid path index' do
      it 'does not queue the request' do
        allow(@scanner).to receive(:possible_paths) { ['/foo', '/bar'] }
        @scanner.queue_requests('foo', 3)
        @scanner.queue_requests('bar', 4)
        expect(@scanner.hydra.queued_requests.length).to eq 0
      end
    end
  end

  describe '#process_result' do
    context 'when passed a valid XML string' do
      xml = %(
        <?xml version="1.0" encoding="utf-8"?>
          <extension type="component" version="3.1" method="upgrade">
            <name>com_admin</name>
            <author>Joomla! Project</author>
            <authorUrl>www.joomla.org</authorUrl>
            <version>3.0.0</version>
            <description>COM_ADMIN_XML_DESCRIPTION</description>
          </extension>
        )

      extension_path = '/components/com_admin/'
      manifest_uri = '/components/com_admin/admin.xml'
      ext = { 'vulns' => [] }

      it 'returns a hash from the extracted data' do
        res = @scanner.process_result(ext, extension_path, manifest_uri, xml)
        expect(res).to be_an_instance_of Hash
        expect(res[:version]).to be_an_instance_of Gem::Version
        expect(res[:version]).to eq Gem::Version.new('3.0.0')
        expect(res[:name]).to eq 'com_admin'
        expect(res[:author]).to eq 'Joomla! Project'
        expect(res[:author_url]).to eq 'www.joomla.org'
        expect(res[:extension_url]).to eq target_uri + extension_path
        expect(res[:manifest_url]).to eq target_uri + manifest_uri
        expect(res[:description]).to eq 'COM_ADMIN_XML_DESCRIPTION'
      end
    end

    context 'when passed an invalid XML string' do
      xml = 'invalid xml string'
      extension_path = '/components/com_admin/'
      manifest_uri = '/components/com_admin/admin.xml'
      ext = { 'vulns' => [] }

      it 'returns a hash with empty values' do
        res = @scanner.process_result(ext, extension_path, manifest_uri, xml)
        expect(res).to be_an_instance_of Hash
        expect(res[:version]).to eq Gem::Version.new('')
        expect(res[:name]).to be_empty
        expect(res[:author]).to be_empty
        expect(res[:author_url]).to be_empty
        expect(res[:description]).to be_empty
      end
    end
  end

  describe '@@version_is_vulnerable' do
    context 'when no vulnerable range is specified' do
      it 'returns true' do
        version = Gem::Version.new('1.0')
        res = ExtensionScanner.version_is_vulnerable(version, {})
        expect(res).to eq true
      end
    end

    context 'when all versions below a specific version are vulnerable' do
      vuln = { 'fixed_in' => '2.5' }
      it 'returns true if the version is older than the fixed version' do
        version = Gem::Version.new('1.0')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq true
      end

      it 'returns false if the version is the fixed version' do
        version = Gem::Version.new('2.5')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq false
      end

      it 'returns false if the version is newer than the fixed version' do
        version = Gem::Version.new('3.0')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq false
      end
    end

    context 'when a specific range of versions are vulnerable' do
      vuln = { 'introduced_in' => '2.0', 'fixed_in' => '2.5' }
      it 'returns false if the version is older than the first vulnerable version' do
        version = Gem::Version.new('1.0')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq false
      end

      it 'returns false if the version is newer than the fixed version' do
        version = Gem::Version.new('2.6')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq false
      end

      it 'returns false if the version is the fixed version' do
        version = Gem::Version.new('2.5')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq false
      end

      it 'returns true if the version is newer than the first vulnerable version and older than the fixed version' do
        version = Gem::Version.new('2.2')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq true
      end

      it 'returns true if the version is the first vulnerable version' do
        version = Gem::Version.new('2.0')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq true
      end
    end

    context 'when multiple ranges of versions are vulnerable' do
      vuln = { 
        'ranges' => [
          {
            'introduced_in' => '2.0',
            'fixed_in' => '2.5'
          },
          {
            'introduced_in' => '3.5',
            'fixed_in' => '3.8'
          }
        ]
      }

      it 'returns false if the version does not fall inside any range' do
        version = Gem::Version.new('2.8')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq false
      end

      it 'returns true if the version is within one of the ranges' do
        version = Gem::Version.new('3.7')
        res = ExtensionScanner.version_is_vulnerable(version, vuln)
        expect(res).to eq true
      end
    end
  end
end