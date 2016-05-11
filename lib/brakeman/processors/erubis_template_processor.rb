require 'brakeman/processors/template_processor'

#Processes ERB templates using Erubis instead of erb.
class Brakeman::ErubisTemplateProcessor < Brakeman::TemplateProcessor

  #s(:call, TARGET, :method, ARGS)
  def process_call exp
    target = exp.target
    if sexp? target
      target = process target
    end

    exp.target = target
    exp.arglist = process exp.arglist
    method = exp.method

    #_buf is the default output variable for Erubis
    if node_type?(target, :lvar, :ivar) and (target.value == :_buf or target.value == :@output_buffer)
      if method == :<< or method == :safe_concat

        arg = normalize_output(exp.first_arg)

        if arg.node_type == :str #ignore plain strings
          ignore
        elsif node_type? target, :ivar and target.value == :@output_buffer
          s = Sexp.new :escaped_output, arg
          s.line(exp.line)
          @current_template.add_output s
          s
        else
          s = Sexp.new :output, arg
          s.line(exp.line)
          @current_template.add_output s
          s
        end
      elsif method == :to_s
        ignore
      else
        abort "Unrecognized action on buffer: #{method}"
      end
    elsif target == nil and method == :render
      make_render_in_view exp
    else
      exp
    end
  end

  #Process blocks, ignoring :ignore exps
  def process_block exp
    exp = exp.dup
    exp.shift
    exp.map! do |e|
      res = process e
      if res.empty? or res == ignore
        nil
      else
        res
      end
    end
    block = Sexp.new(:rlist).concat(exp).compact
    block.line(exp.line)
    block
  end

  #Look for assignments to output buffer that look like this:
  #  @output_buffer.append = some_output
  #  @output_buffer.safe_append = some_output
  #  @output_buffer.safe_expr_append = some_output
  def process_attrasgn exp
    if exp.target.node_type == :ivar and exp.target.value == :@output_buffer
      if append_method?(exp.method)
        exp.first_arg = process(exp.first_arg)
        arg = normalize_output(exp.first_arg)

        if arg.node_type == :str or freeze_call? arg
          ignore
        elsif safe_append_method?(exp.method)
          s = Sexp.new :output, arg
          s.line(exp.line)
          @current_template.add_output s
          s
        else
          s = Sexp.new :escaped_output, arg
          s.line(exp.line)
          @current_template.add_output s
          s
        end
      else
        super
      end
    else
      super
    end
  end

  private
  def append_method?(method)
    method == :append= || safe_append_method?(method)
  end

  def safe_append_method?(method)
    method == :safe_append= || method == :safe_expr_append=
  end

  def freeze_call? exp
    call? exp and exp.method == :freeze and string? exp.target
  end

  def normalize_output arg
    if call? arg and [:to_s, :html_safe!, :freeze].include? arg.method
      arg.target
    elsif node_type? arg, :if
      branches = [arg.then_clause, arg.else_clause].compact

      if branches.empty?
        s(:nil)
      elsif branches.length == 2
        Sexp.new(:or, *branches)
      else
        branches.first
      end
    else
      arg
    end
  end
end
