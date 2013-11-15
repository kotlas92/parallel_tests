module ParallelTests
  class Grouper
    class << self
      def by_steps(tests, num_groups, options)
        features_with_steps = build_features_with_steps(tests, options)
        in_even_groups_by_size(features_with_steps, num_groups)
      end

      def in_even_groups_by_size(items_with_sizes, num_groups, options = {})
        groups = Array.new(num_groups) { {:items => [], :size => 0} }

        # add all files that should run in a single process to one group
        (options[:single_process] || []).each do |pattern|
          matched, items_with_sizes = items_with_sizes.partition { |item, size| item =~ pattern }
          matched.each { |item, size| add_to_group(groups.first, item, size) }
        end

        groups_to_fill = (options[:isolate] ? groups[1..-1] : groups)

        # add all other files
        largest_first(items_with_sizes).each do |item, size|
          smallest = smallest_group(groups_to_fill)
          add_to_group(smallest, item, size)
        end

        report_features_balancing(groups)

        groups.map!{|g| g[:items].sort }

        groups
      end

      def by_weight(tests, num_groups, options)
        features_with_steps = build_features_with_weight(tests, options)
        in_even_groups_by_size(features_with_steps, num_groups)
      end

      private

      def largest_first(files)
        files.sort_by{|item, size| size }.reverse
      end

      def smallest_group(groups)
        groups.min_by{|g| g[:size] }
      end

      def add_to_group(group, item, size)
        group[:items] << item
        group[:size] += size
      end

      def build_features_with_steps(tests, options)
        require 'parallel_tests/gherkin/listener'
        listener = ParallelTests::Gherkin::Listener.new
        listener.ignore_tag_pattern = Regexp.compile(options[:ignore_tag_pattern]) if options[:ignore_tag_pattern]
        parser = ::Gherkin::Parser::Parser.new(listener, true, 'root')
        tests.each{|file|
          parser.parse(File.read(file), file, 0)
        }
        listener.collect.sort_by{|_,value| -value }
      end

      def build_features_with_weight(tests, options)
        result = []

        tests.each do |file|
          file_content = []
          File.open(file).read.each_line{|line| file_content << line}
          if file_content.first[/weight ([0-9]+)/]
            weight = $1.to_i
          else
            weight = 1
          end
          result << [file, weight]
        end

        result
      end

      def report_features_balancing(groups)
        $stdout.puts '='*20
        $stdout.puts "Grouping features:\n"
        groups.each_with_index do |group, index|
          $stdout.puts "Group number #{index}"
          $stdout.puts group[:items].join("\n")
          $stdout.puts "Total weight: #{group[:size]}"
          $stdout.puts '-'*20
        end
        $stdout.puts '='*20
        $stdout.flush
      end
    end
  end
end
