# frozen_string_literal: true

require 'riemann/tools/syslog_ng'

RSpec.describe Riemann::Tools::SyslogNg do
  subject(:tool) { described_class.new }

  let(:statistics) do
    <<~STATISTICS
      destination;d_mail;;a;processed;531
      global;internal_source;;a;dropped;0
      source;s_sys;;a;processed;918589
      src.journald;s_sys#0;journal;fake;processed;912500
      dst.riemann;d_riemann#0;riemann,riemann.example.com,5555;a;written;1380560
      .
    STATISTICS
  end

  before do
    socket = double
    allow(socket).to receive(:gets).and_return(*(["SourceName;SourceId;SourceInstance;State;Type;Number\n"] + statistics.lines))
    allow(socket).to receive(:puts).with('STATS CSV')

    allow(UNIXSocket).to receive(:new).and_return(socket)
  end

  describe '#tick' do
    context 'with default config' do
      it 'reports all metrics' do
        allow(tool).to receive(:report)
        tool.tick
        expect(tool).to have_received(:report).exactly(5).times
      end
    end

    context 'with SourceName filtering' do
      before do
        ARGV.replace(['--source-name', 'dst.riemann'])
      end

      it 'reports metrics with the correct SourceName' do
        allow(tool).to receive(:report)
        tool.tick
        expect(tool).to have_received(:report).once
      end
    end

    context 'with SourceId filtering' do
      before do
        ARGV.replace(['--source-id', 'internal_source'])
      end

      it 'reports metrics with the correct SourceId' do
        allow(tool).to receive(:report)
        tool.tick
        expect(tool).to have_received(:report).once
      end
    end

    context 'with SourceInstance filtering' do
      before do
        ARGV.replace(['--source-instance', 'journal'])
      end

      it 'reports metrics with the correct SourceInstance' do
        allow(tool).to receive(:report)
        tool.tick
        expect(tool).to have_received(:report).once
      end
    end

    context 'with State filtering' do
      before do
        ARGV.replace(['--state', 'fake'])
      end

      it 'reports metrics with the correct State' do
        allow(tool).to receive(:report)
        tool.tick
        expect(tool).to have_received(:report).exactly(1).times
      end
    end

    context 'with Type filtering' do
      before do
        ARGV.replace(['--type', 'dropped'])
      end

      it 'reports metrics with the correct Type' do
        allow(tool).to receive(:report)
        tool.tick
        expect(tool).to have_received(:report).exactly(1).times
      end
    end

    context 'with metrics above threshold' do
      let(:statistics) do
        <<~STATISTICS
          dst.riemann;d_riemann#0;riemann,riemann.example.com,5555;a;queued;204
          dst.riemann;d_riemann#0;riemann,riemann.example.com,5555;a;dropped;0
          dst.riemann;d_riemann#1;riemann,riemann.example.com,5555;a;queued;404
          dst.riemann;d_riemann#1;riemann,riemann.example.com,5555;a;dropped;1
          dst.riemann;d_riemann#2;riemann,riemann.example.com,5555;a;queued;4040
          dst.riemann;d_riemann#2;riemann,riemann.example.com,5555;a;dropped;1000
          .
        STATISTICS
      end

      before do
        allow(tool).to receive(:report)
        tool.tick
      end

      it 'report correct state with few queued events' do
        expect(tool).to have_received(:report).with({ metric: 204, service: 'dst.riemann;d_riemann#0;riemann,riemann.example.com,5555;a;queued', state: 'ok' })
      end

      it 'report correct state with some queued events' do
        expect(tool).to have_received(:report).with({ metric: 404, service: 'dst.riemann;d_riemann#1;riemann,riemann.example.com,5555;a;queued', state: 'warning' })
      end

      it 'report correct state with a lot of queued events' do
        expect(tool).to have_received(:report).with({ metric: 4040, service: 'dst.riemann;d_riemann#2;riemann,riemann.example.com,5555;a;queued', state: 'critical' })
      end

      it 'report correct state with no dropped events' do
        expect(tool).to have_received(:report).with({ metric: 0, service: 'dst.riemann;d_riemann#0;riemann,riemann.example.com,5555;a;dropped', state: 'ok' })
      end

      it 'report correct state with some dropped events' do
        expect(tool).to have_received(:report).with({ metric: 1, service: 'dst.riemann;d_riemann#1;riemann,riemann.example.com,5555;a;dropped', state: 'critical' })
      end

      it 'report correct state with a lot of dropped events' do
        expect(tool).to have_received(:report).with({ metric: 1000, service: 'dst.riemann;d_riemann#2;riemann,riemann.example.com,5555;a;dropped', state: 'critical' })
      end
    end

    context 'with custom formatting' do
      before do
        ARGV.replace(['--format', '%<source_name>s %<type>s'])
      end

      let(:statistics) do
        <<~STATISTICS
          dst.riemann;d_riemann#0;riemann,riemann.example.com,5555;a;queued;204
          .
        STATISTICS
      end

      it 'reports the correct service' do
        allow(tool).to receive(:report)
        tool.tick
        expect(tool).to have_received(:report).with({ metric: 204, service: 'dst.riemann queued', state: 'ok' })
      end
    end
  end
end
