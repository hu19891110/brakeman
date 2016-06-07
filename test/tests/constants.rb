class ConstantTests < Test::Unit::TestCase
  def setup
    @constants = Brakeman::Constants.new
  end

  def assert_alias expected, original, full = false
    tracker = Brakeman::Tracker.new(nil)
    original_sexp = Brakeman::BaseProcessor.new(tracker).process(RubyParser.new.parse original)
    expected_sexp = Brakeman::BaseProcessor.new(tracker).process(RubyParser.new.parse expected)
    processed_sexp = Brakeman::AliasProcessor.new(tracker).process_safely original_sexp

    if full
      assert_equal expected_sexp, processed_sexp
    else
      assert_equal expected_sexp, processed_sexp.last
    end
  end

  def test_constants_yeah
    assert_alias <<-OUTPUT, <<-INPUT, true
      class A
        def x
          puts 1
        end
      end

      X = 1
    OUTPUT
      class A
        def x
          puts X
        end
      end

      X = 1
    INPUT
  end

  def test_constants_issue_453
    assert_alias <<-OUTPUT, <<-INPUT, true
    class User < ActiveRecord::Base
      FOO = ['Baz']
      BAR = 'Qux'

      def variations
        'Baz'.constantize
        'Baz'.constantize
        'Qux'.constantize
        'Qux'.constantize
      end
    end
    OUTPUT
    class User < ActiveRecord::Base
      FOO = ['Baz']
      BAR = 'Qux'

      def variations
        User::FOO.first.constantize
        FOO.first.constantize
        User::BAR.constantize
        BAR.constantize
      end
    end
    INPUT
  end

  def test_constants_basic_lookup
    @constants.add :A, s(:lit, 1)

    assert_equal s(:lit, 1), @constants.get_literal(s(:const, :A))
  end

  def test_constants_get_literal
    a_b_c = s(:colon2, s(:colon2, s(:const, :A), :B), :C)
    @constants.add s(:const, :A), s(:lit, 1)
    @constants.add a_b_c, s(:lit, 2)
    @constants.add s(:const, :D), s(:const, :D)

    assert_equal s(:lit, 1), @constants.get_literal(s(:const, :A))
    assert_equal s(:lit, 2), @constants.get_literal(a_b_c)
    assert_equal s(:lit, 2), @constants.get_literal(s(:colon2, s(:const, :B), :C))
    assert_equal s(:lit, 2), @constants.get_literal(s(:colon2, s(:colon2, s(:colon3, :A), :B), :C) )
    assert_nil @constants.get_literal(s(:colon2, s(:colon3, :B), :C)) # top-level B
    assert_nil @constants.get_literal(s(:colon2, s(:const, :A), :C))
    assert_nil @constants.get_literal(s(:colon2, s(:const, :C), :B)) # backwards
    assert_nil @constants.get_literal(s(:const, :D)) # not a literal
  end

  def test_constants_lookup
    @constants.add s(:const, :A), s(:lit, 1)
    @constants.add s(:colon2, s(:const, :A), :B), s(:lit, 2)
    @constants.add s(:const, :D), s(:const, :D)

    assert_equal s(:lit, 1), @constants[s(:const, :A)]
    assert_equal s(:lit, 2), @constants[s(:colon2, s(:const, :A), :B)]
    assert_equal s(:const, :D), @constants[s(:const, :D)]
  end

  def test_constants_large
    assert_alias <<-OUTPUT, <<-INPUT, true
    module A
      def x
        p [1, 2, 3, 4, 5, 6, 7, 8, 9, :'...']
      end
    end

    X = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    OUTPUT
    module A
      def x
        p X
      end
    end

    X = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    INPUT
  end
end
