#!/usr/bin/env ruby
# Encoding: UTF-8

################################################################################

describe Poefy::Poem, "-- Postgres" do

  before(:all) do
    require 'poefy/pg'
    @root = Poefy.root
    dbs = %w{spec_test_tiny spec_shakespeare spec_whitman}
    dbs.each do |db_name|
      Poefy::Database.single_exec! <<-SQL
        SET client_min_messages TO WARNING;
        DROP TABLE IF EXISTS #{db_name};
      SQL
    end
  end

  after(:all) do
    dbs = %w{spec_test_tiny spec_shakespeare spec_whitman}
    dbs.each do |db_name|
      Poefy::Database.single_exec! <<-SQL
        SET client_min_messages TO WARNING;
        DROP TABLE IF EXISTS #{db_name};
      SQL
    end
  end

  ##############################################################################

  describe "using tiny dataset 'spec_test_tiny'" do
    corpus = "spec_test_tiny"

    # Create a small corpus of a few rhymes.
    text_array = %w{man plan flan can dan fish dish wish bee sea tree flea}
    text_array.map!{ |i| 'a ' + i }
    text_string = text_array.join("\n")
    row_count = text_array.count

    before(:each) do
      @poefy = Poefy::Poem.new(corpus, { proper: false })
    end
    after(:each) do
      @poefy.close
    end
    it "initialised object not nil" do
      expect(@poefy).to_not be_nil
    end

    # Create corpora in the three different ways.
    describe "@poefy#make_database!" do

      it "Use array of strings" do
        @poefy.make_database! text_array
        expect(@poefy.corpus.exist?).to be true
        expect(@poefy.corpus.count).to be row_count
        poem = @poefy.poem({ rhyme: 'aabb' })
        expect(poem.count).to be 4
      end

      it "Use one long newline delimited string" do
        @poefy.make_database! text_string
        expect(@poefy.corpus.exist?).to be true
        expect(@poefy.corpus.count).to be row_count
        poem = @poefy.poem({ rhyme: 'aabb' })
        expect(poem.count).to be 4
      end

      it "Use text lines from a file" do

        # Create a temp file.
        tmp = Tempfile.new('spec-', Poefy.root + '/spec')
        text_path = tmp.path
        tmp.write text_string
        tmp.close

        @poefy.make_database! text_path
        expect(@poefy.corpus.exist?).to be true
        expect(@poefy.corpus.count).to be row_count
        poem = @poefy.poem({ rhyme: 'aabb' })
        expect(poem.count).to be 4

        # Delete the temp file.
        tmp.delete
      end
    end

    # Make sure that the description can be updated as specified
    #   and that it doesn't cause SQL injection.
    describe "corpus description using #desc=" do
      it "@poefy.corpus.desc is initially empty" do
        expect(@poefy.corpus.desc).to eq ''
      end

      values = [
        "test",
        " -- test",
        "; -- test",
        "test' -- ",
        "test'' -- ",
        "'test' -- ",
        "'test'' -- ",
        "Shakespeare's sonnets",
        "Shakespeare's -- sonnets",
        "Shakespeare's; -- sonnets",
        "test' ; INSERT INTO spec_test_tiny VALUES('foo') -- ",
        "105 OR 1=1",
        "' or ''='"
      ]
      values.each do |value|
        it "@poefy.corpus.desc = #{value}" do
          @poefy.corpus.desc = value
          expect(@poefy.corpus.desc).to eq value
          expect(@poefy.corpus.count).to be row_count
        end
      end
    end

    describe ":rhyme option" do

      describe "should raise Poefy::MissingFormOrRhyme" do
        it "blank, no argument" do
          expect {
            @poefy.poem
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
        it "({  })" do
          expect {
            @poefy.poem ({  })
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
        it "({ rhyme: nil })" do
          expect {
            @poefy.poem ({ rhyme: nil })
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
        it "({ rhyme: ' ' })" do
          expect {
            @poefy.poem ({ rhyme: ' ' })
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
        it "({ rhyme: '' })" do
          expect {
            @poefy.poem ({ rhyme: '' })
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
      end

      describe "should return correct number of lines" do
        rhymes = %w{a b z A aa ab zz AA AB AA1 A1 B1 Z1 AB1 A1A1A1A1B1B1B1B1B1}
        rhymes += ['A1A1A1 A1A1A1 B1B1B1B1B1B1','a b c a b c']
        rhymes += ['   abc','abc   ','   abc   ']
        rhymes += ['n   aaa   n','n   aXXXa   N1']
        rhymes.each do |i|
          it "({ rhyme: '#{i}' })" do
            poem = @poefy.poem ({ rhyme: i })
            expect(poem.count).to be i.gsub(/[0-9]/,'').length
          end
        end
      end

      describe "should accept characters other than number" do
        rhymes = %w{. , : .. ., ,, :: (()) @ ~ <<>< A1A1A1...a;}
        rhymes.each do |i|
          it "({ rhyme: '#{i}' })" do
            poem = @poefy.poem ({ rhyme: i })
            expect(poem.count).to be i.gsub(/[0-9]/,'').length
          end
        end
      end

      describe "should raise error if can't parse rhyme string" do
        rhymes = %w{a1 b1 ab1 Ab1 AAAAABb1 1 1111 1122 11221 ;;::1. }
        rhymes += ['AA Bb1','11 11','11 1 1','..1.']
        rhymes.each do |i|
          it "({ rhyme: '#{i}' })" do
            expect {
              @poefy.poem ({ rhyme: i })
            }.to raise_error(Poefy::RhymeError)
          end
        end
      end

      describe "should raise error if can't complete rhyme string" do
        rhymes = %w{aaaaaa abcd aaaaabbbbb}
        rhymes.each do |i|
          it "({ rhyme: '#{i}' })" do
            expect {
              @poefy.poem ({ rhyme: i })
            }.to raise_error(Poefy::NotEnoughData)
          end
        end
      end

      describe "should correctly repeat uppercase lines" do
        lines = 200
        it "({ rhyme: 'A' * #{lines} })" do
          poem = @poefy.poem ({ rhyme: 'A' * lines })
          expect(poem.count).to be lines
          expect(poem.uniq.count).to be 1
        end
        it "({ rhyme: ('A'..'C').to_a.map { |i| i * #{lines} }.join })" do
          rhyme = ('A'..'C').to_a.map { |i| i * lines }.join
          poem = @poefy.poem ({ rhyme: rhyme })
          expect(poem.count).to be lines * 3
          expect(poem.uniq.count).to be 3
        end
      end

      describe "should raise error if can't complete repeating rhyme string" do
        lines = 200
        it "({ rhyme: ('A'..'D').to_a.map { |i| i * #{lines} }.join })" do
          rhyme = ('A'..'D').to_a.map { |i| i * lines }.join
          expect {
            @poefy.poem ({ rhyme: rhyme })
          }.to raise_error(Poefy::NotEnoughData)
        end
      end

    end

    describe ":form option" do

      describe "should return correct number of lines" do
        it "({ form: :default })" do
          poem = @poefy.poem ({ form: :default })
          expect(poem.count).to be 1
        end
      end

      describe "should raise error if given a named form it can't fulfil" do
        it "({ form: 'sonnet' })" do
          expect {
            @poefy.poem ({ form: 'sonnet' })
          }.to raise_error(Poefy::NotEnoughData)
        end
        it "({ form: :villanelle })" do
          expect {
            @poefy.poem ({ form: 'villanelle' })
          }.to raise_error(Poefy::NotEnoughData)
        end
      end

      describe "should raise error if given a junk named form" do
        it "({ form: 'sonnet_junk' })" do
          expect {
            @poefy.poem ({ form: 'sonnet_junk' })
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
        it "({ form: :not_a_form })" do
          expect {
            @poefy.poem ({ form: :not_a_form })
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
        it "({ form: :not_a_form, indent: '0010' })" do
          expect {
            @poefy.poem ({ form: :not_a_form, indent: '0010' })
          }.to raise_error(Poefy::MissingFormOrRhyme)
        end
      end

      describe "should be valid if given a junk named form, and a rhyme" do
        it "({ form: :not_a_form, rhyme: 'abcb' })" do
          poem = @poefy.poem ({ form: :not_a_form, rhyme: 'abcb' })
          expect(poem.count).to be 4
        end
      end

      describe "should overwrite a named form if another option is specified" do
        it "({ form: 'default', rhyme: 'ab' })" do
          poem = @poefy.poem ({ form: 'default', rhyme: 'ab' })
          expect(poem.count).to be 2
        end
        it "({ form: :villanelle, rhyme: 'abcb' })" do
          poem = @poefy.poem ({ form: :villanelle, rhyme: 'abcb' })
          expect(poem.count).to be 4
        end
      end
    end
  end

  ##############################################################################

  describe "using dataset 'spec_shakespeare'" do

    file_txt = "shakespeare_sonnets.txt"
    file_db  = "spec_shakespeare"

    # All the Shakespeare lines are pentameter, so some forms should fail.
    forms      = Poefy::PoeticForms::POETIC_FORMS
    forms_fail = [:limerick, :haiku, :common, :ballad, :double_dactyl]
    forms_pass = forms.keys - forms_fail

    before(:each) do
      @poefy = Poefy::Poem.new(file_db, { proper: false })
    end
    after(:each) do
      @poefy.close
    end

    it "initialised object not nil" do
      expect(@poefy).to_not be_nil
    end

    describe "#make_database( '#{@root}/data/#{file_txt}', true )" do
      it "should make the database '#{@root}/data/#{file_db}" do
        input = `sed '/[a-z]/!d' #{@root}/data/#{file_txt}`
        @poefy.make_database! input
        expect(@poefy.corpus.exist?).to be true
      end
    end

    describe "using acrostic option" do
      describe "should return correct number of lines" do
        it "({ form: :sonnet, acrostic: 'pauldpthompson' })" do
          poem = @poefy.poem ({ form: :sonnet,
                                acrostic: 'pauldpthompson' })
          expect(poem.count).to be 14
        end
      end
      describe "should raise Poefy::NotEnoughData" do
        it "({ form: :sonnet, acrostic: 'qqqqqqqqqqqqqq' })" do
          expect {
            @poefy.poem ({ form: :sonnet,
                           acrostic: 'qqqqqqqqqqqqqq' })
          }.to raise_error(Poefy::NotEnoughData)
        end
      end
    end

    describe "using form string" do
      describe "should return correct number of lines" do

        # Make sure each form's lines match the expected output.
        # Generate a few to be sure.
        forms_pass.each do |form|
          it "({ form: #{form} })" do
            10.times do
              poem = @poefy.poem ({ form: form })
              expect(poem.count).to satisfy do |c|
                [*forms[form][:rhyme]].map do |r|
                  r.gsub(/[0-9]/,'').length
                end.include?(c)
              end
            end
          end
        end
      end

      describe "should raise Poefy::NotEnoughData" do
        forms_fail.each do |form|
          it "({ form: #{form} })" do
            4.times do
              expect {
                @poefy.poem ({ form: form })
              }.to raise_error(Poefy::NotEnoughData)
            end
          end
        end
      end
    end

    describe "make sonnets" do
      sonnet_options = [
        { rhyme: 'ababcdcdefefgg' },
        { rhyme: 'abab cdcd efef gg', indent: '0101 0101 0011 01' },
        { form: 'sonnet' },
        { form: :sonnet, syllable: 0 },
        { form: :sonnet, syllable: 10 },
        { form: :sonnet, regex: /^[A-Z].*$/ },
        { form: :sonnet, regex: '^[A-Z].*$' },
        { form: :sonnet, acrostic: 'pauldpthompson' },
        { form: 'sonnet', indent: '01010101001101' },
        { form: 'sonnet', proper: false }
      ]
      sonnet_options.each do |option|
        it "#{option}" do
          4.times do
            poem = @poefy.poem(option)
            expect(poem).to_not be_nil
          end
        end
      end
    end
  end

  ##############################################################################

  describe "using dataset 'spec_whitman'" do

    file_txt = "whitman_leaves.txt"
    file_db  = "spec_whitman"

    # There's a good mix of syllable count, so all forms should pass.
    forms      = Poefy::PoeticForms::POETIC_FORMS
    forms_pass = forms.keys

    before(:each) do
      @poefy = Poefy::Poem.new(file_db, { proper: false })
    end
    after(:each) do
      @poefy.close
    end

    it "initialised object not nil" do
      expect(@poefy).to_not be_nil
    end

    describe "#make_database( '#{@root}/data/#{file_txt}', true )" do
      it "should make the database '#{@root}/data/#{file_db}" do
        input = `sed '/[a-z]/!d' #{@root}/data/#{file_txt}`
        @poefy.make_database! input
        expect(@poefy.corpus.exist?).to be true
      end
    end

    describe "using form string" do
      describe "should return correct number of lines" do

        # Make sure each form's lines match the expected output.
        # Generate a few to be sure.
        forms_pass.each do |form|
          it "({ form: #{form} })" do
            10.times do
              poem = @poefy.poem ({ form: form })
              expect(poem.count).to satisfy do |c|
                [*forms[form][:rhyme]].map do |r|
                  r.gsub(/[0-9]/,'').length
                end.include?(c)
              end
            end
          end
        end
      end
    end

    describe "make sonnets" do
      sonnet_options = [
        { rhyme: 'ababcdcdefefgg' },
        { rhyme: 'abab cdcd efef gg', indent: '0101 0101 0011 01' },
        { form: 'sonnet' },
        { form: :sonnet, syllable: 0 },
        { form: :sonnet, syllable: 10 },
        { form: :sonnet, regex: /^[A-Z].*$/ },
        { form: :sonnet, regex: '^[A-Z].*$' },
        { form: :sonnet, acrostic: 'pauldpthompson' },
        { form: 'sonnet', indent: '01010101001101' },
        { form: 'sonnet', proper: false }
      ]
      sonnet_options.each do |option|
        it "#{option}" do
          4.times do
            poem = @poefy.poem(option)
            expect(poem).to_not be_nil
          end
        end
      end
    end

    describe "using syllable string" do

      it "({ rhyme: 'abcb defe', syllable: '[8,6,8,6,0,8,6,8,6]' })" do
        options = {
          rhyme:    'abcb defe',
          syllable: '[8,6,8,6,0,8,6,8,6]'
        }
        poem = @poefy.poem (options)
        expect(poem.count).to be options[:rhyme].length
      end

      it "({ rhyme: 'abcb defe', syllable: '[8,6,8,6,8,6,8,6]' })" do
        options = {
          rhyme:    'abcb defe',
          syllable: '[8,6,8,6,8,6,8,6]'
        }
        poem = @poefy.poem (options)
        expect(poem.count).to be options[:rhyme].length
      end
    end
  end

  ##############################################################################

  describe "reusing the same Poem instance" do
    it "should correctly merge the option hashes" do

      # Default to use rondeau poetic form, and proper sentence validation
      poefy = Poefy::Poem.new(
        'spec_shakespeare',
        { form: 'rondeau', proper: true }
      )

      # Generate a properly sentenced rondeau
      poem = poefy.poem
      expect(poem.count).to be 17

      # Generate a rondeau without proper validation
      poem = poefy.poem ({ proper: false })
      expect(poem.count).to be 17

      # Generate a proper rondeau with a certain indentation
      poem = poefy.poem ({ indent: '01012 0012 010112' })
      expect(poem.count).to be 17

      # Generate other forms
      poem = poefy.poem ({ rhyme: 'abbaabbacdecde' })
      expect(poem.count).to be 14
      poem = poefy.poem ({ form: 'sonnet' })
      expect(poem.count).to be 14
      poem = poefy.poem ({ form: 'ballade' })
      expect(poem.count).to be 31

      # Generate a default rondeau again
      poem = poefy.poem
      expect(poem.count).to be 17

      poefy.close
    end
  end

  ##############################################################################

  describe "using the transform option" do

    it "should correctly transform the output 1" do
      poefy = Poefy::Poem.new :spec_shakespeare
      transform_hash = {
         4 => proc { |line, num, poem| line.upcase },
        12 => proc { |line, num, poem| line.upcase }
      }
      poem = poefy.poem({ form: :sonnet, transform: transform_hash })
      expect(poem.count).to be 14
      expect(poem[3]).to  eq poem[3].upcase
      expect(poem[11]).to eq poem[11].upcase
      poefy.close
    end

    it "should correctly transform the output 2" do
      poefy = Poefy::Poem.new :spec_shakespeare
      transform_hash = {
         4 => proc { |line, num, poem| poem.count },
        -3 => proc { |line, num, poem| poem.count },
         7 => proc { |line, num, poem| 'test string' }
      }
      poem = poefy.poem({ form: :sonnet, transform: transform_hash })
      expect(poem.count).to be 14
      expect(poem[3]).to  eq '14'
      expect(poem[11]).to eq '14'
      expect(poem[6]).to  eq 'test string'
      poefy.close
    end

    it "should correctly transform the output 3" do
      poefy = Poefy::Poem.new :spec_shakespeare
      transform_proc = proc { |line, num, poem| line.downcase }
      poem = poefy.poem({ form: :sonnet, transform: transform_proc })
      expect(poem.count).to be 14
      poem.each do |i|
        expect(i).to eq i.downcase
      end
      poefy.close
    end

    it "should correctly transform the output 4" do
      poefy = Poefy::Poem.new :spec_shakespeare
      transform_proc = proc { |line, num, poem| "#{num} #{line.downcase}" }
      poem = poefy.poem({ form: :sonnet, transform: transform_proc })
      expect(poem.count).to be 14
      poem.each.with_index do |line, index|
        expect(line).to eq line.downcase
        first_word = line.split(' ').first
        expect(first_word).to eq (index + 1).to_s
      end
      poefy.close
    end
  end

  ##############################################################################

  describe "using the form_from_text option" do
    before(:all) do
      @text = <<-TEXT
        [Chorus 1]
        Oh yeah, I'll tell you something
        I think you'll understand
        When I'll say that something
        I want to hold your hand
        I want to hold your hand
        I want to hold your hand

        [Verse 1]
        Oh please, say to me
        You'll let me be your man
        And please, say to me
        You'll let me hold your hand
        I'll let me hold your hand
        I want to hold your hand
      TEXT
      @line_count = @text.split("\n").count
    end

    it "should use the exact poetic form 1" do
      poefy = Poefy::Poem.new(:spec_whitman, {
        form_from_text: @text
      })
      poem = poefy.poem
      poem.map!(&:strip!)
      expect(poem.count).to be @line_count
      expect(poem[0]).to eq "[Chorus 1]"
      expect(poem[8]).to eq "[Verse 1]"
      expect(poem[5]).to eq poem[4]
      expect(poem[6]).to eq poem[4]
      poefy.close
    end

    it "should use the exact poetic form 2" do
      poefy = Poefy::Poem.new :spec_whitman
      poem = poefy.poem({
        form_from_text: @text
      })
      poem.map!(&:strip!)
      expect(poem.count).to be @line_count
      expect(poem[0]).to eq "[Chorus 1]"
      expect(poem[8]).to eq "[Verse 1]"
      expect(poem[5]).to eq poem[4]
      expect(poem[6]).to eq poem[4]
      poefy.close
    end

    it "should correctly modify the poetic form 1" do
      poefy = Poefy::Poem.new(:spec_whitman, {
        form_from_text: @text,
        syllable: 6
      })
      poem = poefy.poem
      poem.map!(&:strip!)
      expect(poem.count).to be @line_count
      expect(poem[0]).to eq "[Chorus 1]"
      expect(poem[8]).to eq "[Verse 1]"
      expect(poem[5]).to eq poem[4]
      expect(poem[6]).to eq poem[4]
      poefy.close
    end

    it "should correctly modify the poetic form 2" do
      poefy = Poefy::Poem.new :spec_whitman
      poem = poefy.poem({
        form_from_text: @text,
        syllable: 6
      })
      poem.map!(&:strip!)
      expect(poem.count).to be @line_count
      expect(poem[0]).to eq "[Chorus 1]"
      expect(poem[8]).to eq "[Verse 1]"
      expect(poem[5]).to eq poem[4]
      expect(poem[6]).to eq poem[4]
      poefy.close
    end

    it "should correctly modify the poetic form 3" do
      poefy = Poefy::Poem.new(:spec_whitman, {
        form_from_text: @text
      })
      poem = poefy.poem({
        syllable: 6
      })
      poem.map!(&:strip!)
      expect(poem.count).to be @line_count
      expect(poem[0]).to eq "[Chorus 1]"
      expect(poem[8]).to eq "[Verse 1]"
      expect(poem[5]).to eq poem[4]
      expect(poem[6]).to eq poem[4]
      poefy.close
    end

    it "should correctly replace the poetic form" do
      poefy = Poefy::Poem.new(:spec_whitman, {
        syllable: 6
      })
      poem = poefy.poem({
        form_from_text: @text
      })
      poem.map!(&:strip!)
      expect(poem.count).to be @line_count
      expect(poem[0]).to eq "[Chorus 1]"
      expect(poem[8]).to eq "[Verse 1]"
      expect(poem[5]).to eq poem[4]
      expect(poem[6]).to eq poem[4]
      poefy.close
    end

  end

end

################################################################################
