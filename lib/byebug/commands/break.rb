require 'byebug/command'
require 'byebug/helpers/eval'
require 'byebug/helpers/file'
require 'byebug/helpers/parse'

module Byebug
  #
  # Implements breakpoint functionality
  #
  class BreakCommand < Command
    include Helpers::EvalHelper
    include Helpers::FileHelper
    include Helpers::ParseHelper

    self.allow_in_control = true

    def self.regexp
      /^\s* b(?:reak)? (?:\s+ (.+?))? (?:\s+ if \s+(.+))? \s*$/x
    end

    def self.description
      <<-DESCRIPTION
        b[reak] [file:]line [if expr]
        b[reak] [module::...]class(.|#)method [if expr]

        They can be specified by line or method and an expression can be added
        for conditionally enabled breakpoints.

        #{short_description}
      DESCRIPTION
    end

    def self.short_description
      'Sets breakpoints in the source code'
    end

    def execute
      return puts(help) unless @match[1]

      b = line_breakpoint(@match[1]) || method_breakpoint(@match[1])
      return errmsg(pr('break.errors.location')) unless b

      if syntax_valid?(@match[2])
        return puts(pr('break.created', id: b.id, file: b.source, line: b.pos))
      end

      errmsg(pr('break.errors.expression', expr: @match[2]))
      b.enabled = false
    end

    private

    def line_breakpoint(location)
      line_match = location.match(/^(\d+)$/)
      file_line_match = location.match(/^(.+):(\d+)$/)
      return unless line_match || file_line_match

      file = line_match ? frame.file : file_line_match[1]
      line = line_match ? line_match[1].to_i : file_line_match[2].to_i

      add_line_breakpoint(file, line)
    end

    def method_breakpoint(location)
      location.match(/([^.#]+)[.#](.+)/) do |match|
        klass = target_object(match[1])
        method = match[2].intern

        Breakpoint.add(klass, method, @match[2])
      end
    end

    def target_object(str)
      k = error_eval(str)

      k && k.is_a?(Module) ? k.name : str
    rescue StandardError
      errmsg('Warning: breakpoint source is not yet defined')
      str
    end

    def add_line_breakpoint(file, line)
      raise(pr('break.errors.source', file: file)) unless File.exist?(file)

      fullpath = File.realpath(file)

      if line > n_lines(file)
        raise(pr('break.errors.far_line', lines: n_lines(file), file: fullpath))
      end

      unless Breakpoint.potential_line?(fullpath, line)
        min = [line - 5, 1].max
        max = [line + 5, n_lines(file)].min
        potential_lines = Breakpoint.potential_lines(fullpath)
        valid_breakpoints = File.foreach(fullpath).with_index.map{|src_line, src_lineno|
          next unless (min .. max).include? src_lineno
          b = potential_lines.include?(src_lineno+1) ? '[B]' : '   '
          "#{b} %#{max.to_s.size}d: %s" % [src_lineno+1, src_line]
        }.join
        raise(pr('break.errors.line', file: fullpath, line: line, valid_breakpoints: valid_breakpoints))
      end

      Breakpoint.add(fullpath, line, @match[2])
    end
  end
end
