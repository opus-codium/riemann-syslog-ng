# frozen_string_literal: true

require 'strscan'

require 'riemann/tools'

module Riemann
  module Tools
    class SyslogNg
      include Riemann::Tools

      opt :socket, 'Path to syslog-ng socket', short: :none, type: :string, default: '/var/lib/syslog-ng/syslog-ng.ctl'
      opt :format, 'Format for service name', short: :none, type: :string, default: '%<source_name>s;%<source_id>s;%<source_instance>s;%<state>s;%<type>s'

      opt :source_name, 'Filter on SourceName', short: :none, type: :strings
      opt :source_id, 'Filter on SourceId', short: :none, type: :strings
      opt :source_instance, 'Filter on SourceInstance', short: :none, type: :strings
      opt :state, 'Filter on State', short: :none, type: :strings
      opt :type, 'Filter on Type', short: :none, type: :strings

      opt :queued_warning, 'Queued messages warning threshold', short: :none, default: 300
      opt :queued_critical, 'Queued messages critical threshold', short: :none, default: 1000

      def self.process_stdin
        new.process_stdin
      end

      def initialize
        @socket = UNIXSocket.new(opts[:socket])
      end

      def tick
        statistics.each do |statistic|
          report({
                   service: format(opts[:format], statistic),
                   metric: statistic[:metric],
                   state: statistic_state(statistic[:type], statistic[:metric]),
                 })
        end
      end

      def statistics
        res = []

        @socket.puts 'STATS CSV'
        @socket.gets # discard header
        while (line = @socket.gets.chomp) != '.'
          source_name, source_id, source_instance, state, type, metric = line.split(';')

          next if opts[:source_name] && !opts[:source_name].include?(source_name)
          next if opts[:source_id] && !opts[:source_id].include?(source_id)
          next if opts[:source_instance] && !opts[:source_instance].include?(source_instance)
          next if opts[:state] && !opts[:state].include?(state)
          next if opts[:type] && !opts[:type].include?(type)

          res << {
            source_name: source_name,
            source_id: source_id,
            source_instance: source_instance,
            state: state,
            type: type,
            metric: metric.to_f,
          }
        end

        res
      end

      def statistic_state(type, metric)
        if type == 'dropped'
          metric == 0.0 ? 'ok' : 'critical'
        elsif type == 'queued'
          if metric >= opts[:queued_critical]
            'critical'
          elsif metric >= opts[:queued_warning]
            'warning'
          else
            'ok'
          end
        end
      end
    end
  end
end
