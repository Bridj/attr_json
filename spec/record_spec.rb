require 'spec_helper'

RSpec.describe JsonAttribute::Record do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record

      self.table_name = "products"
      json_attribute :str, :string
      json_attribute :int, :integer
      json_attribute :int_array, :integer, array: true
      json_attribute :int_with_default, :integer, default: 5
    end
  end
  let(:instance) { klass.new }

  [
    [:integer, 12, "12"],
    [:string, "12", 12],
    [:decimal, BigDecimal.new("10.01"), "10.0100"],
    [:boolean, true, "t"],
    [:date, Date.parse("2017-04-28"), "2017-04-28"],
    [:datetime, DateTime.parse("2017-04-04 04:45:00").to_time, "2017-04-04T04:45:00Z"],
    [:float, 45.45, "45.45"]
  ].each do |type, cast_value, uncast_value|
    describe "for primitive type #{type}" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record

          self.table_name = "products"
          json_attribute :value, type
        end
      end
      it "properly saves good #{type}" do
        instance.value = cast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
      it "casts to #{type}" do
        instance.value = uncast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
    end
  end

  it "can set nil" do
    instance.str = nil
    expect(instance.str).to be_nil
    expect(instance.json_attributes).to eq("str" => nil, "int_with_default" => 5)

    instance.save!
    instance.reload

    expect(instance.str).to be_nil
    expect(instance.json_attributes).to eq("str" => nil, "int_with_default" => 5)
  end

  it "supports arrays" do
    instance.int_array = %w(1 2 3)
    expect(instance.int_array).to eq([1, 2, 3])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1, 2, 3])

    instance.int_array = 1
    expect(instance.int_array).to eq([1])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1])
  end

  # TODO: Should it LET you redefine instead, and spec for that? Have to pay
  # attention to store keys too if we let people replace attributes.
  it "raises on re-using attribute name" do
    expect {
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record

        self.table_name = "products"
        json_attribute :value, :string
        json_attribute :value, :integer
      end
    }.to raise_error(ArgumentError, /Can't add, conflict with existing attribute name `value`/)
  end

  context "initialize" do
    it "casts and fills in defaults" do
      o = klass.new(int: "12", str: 12, int_array: "12")

      expect(o.int).to eq 12
      expect(o.str).to eq "12"
      expect(o.int_array).to eq [12]
      expect(o.int_with_default).to eq 5
      expect(o.json_attributes).to eq('int' => 12, 'str' => "12", 'int_array' => [12], 'int_with_default' => 5)
    end
  end

  context "assign_attributes" do
    it "casts" do
      instance.assign_attributes(int: "12", str: 12, int_array: "12")

      expect(instance.int).to eq 12
      expect(instance.str).to eq "12"
      expect(instance.int_array).to eq [12]
      expect(instance.json_attributes).to include('int' => 12, 'str' => "12", 'int_array' => [12], 'int_with_default' => 5)
    end
  end

  context "defaults" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record

        self.table_name = "products"
        json_attribute :str_with_default, :string, default: "DEFAULT_VALUE"
      end
    end

    it "supports defaults" do
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
    end

    it "saves default even without access" do
      instance.save!
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
      instance.reload
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
    end

    it "lets default override with nil" do
      instance.str_with_default = nil
      expect(instance.str_with_default).to eq(nil)
      instance.save
      instance.reload
      expect(instance.str_with_default).to eq(nil)
      expect(instance.json_attributes).to include("str_with_default" => nil)
    end
  end

  context "store keys" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "products"
        include JsonAttribute::Record
        json_attribute :value, :string, default: "DEFAULT_VALUE", store_key: :_store_key
      end
    end

    it "puts the default value in the jsonb hash at the given store key" do
      expect(instance.value).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE")
    end

    it "sets the value at the given store key" do
      instance.value = "set value"
      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")

      instance.save!
      instance.reload

      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")
    end

    it "raises on conflicting store key" do
      expect {
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record

          self.table_name = "products"
          json_attribute :value, :string
          json_attribute :other_thing, :string, store_key: "value"
        end
      }.to raise_error(ArgumentError, /Can't add, store key `value` conflicts with existing attribute/)
    end

    context "inheritance" do
      let(:subklass) do
        Class.new(klass) do
          self.table_name = "products"
          include JsonAttribute::Record
          json_attribute :new_value, :integer, default: "NEW_DEFAULT_VALUE", store_key: :_new_store_key
        end
      end
      let(:subklass_instance) { subklass.new }

      it "includes default values from the parent in the jsonb hash with the correct store keys" do
        expect(subklass_instance.value).to eq("DEFAULT_VALUE")
        expect(subklass_instance.new_value).to eq("NEW_DEFAULT_VALUE")
        expect(subklass_instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE", "_new_store_key" => "NEW_DEFAULT_VALUE")
      end
    end
  end

  context "specified container_attribute" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record
        self.table_name = "products"

        json_attribute :value, :string, container_attribute: :other_attributes
      end
    end

    it "saves in appropriate place" do
      instance.value = "X"
      expect(instance.value).to eq("X")
      expect(instance.other_attributes).to eq("value" => "X")
      expect(instance.json_attributes).to be_blank

      instance.save!
      instance.reload

      expect(instance.value).to eq("X")
      expect(instance.other_attributes).to eq("value" => "X")
      expect(instance.json_attributes).to be_blank
    end

    describe "change default container attribute" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record
          self.table_name = "products"

          self.default_json_container_attribute = :other_attributes

          json_attribute :value, :string
        end
      end
      it "saves in right place" do
        instance.value = "X"
        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("value" => "X")
        expect(instance.json_attributes).to be_blank

        instance.save!
        instance.reload

        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("value" => "X")
        expect(instance.json_attributes).to be_blank
      end
    end

    describe "with store key" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record
          self.table_name = "products"

          json_attribute :value, :string, store_key: "_store_key", container_attribute: :other_attributes
        end
      end

      it "saves with store_key" do
        instance.value = "X"
        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("_store_key" => "X")
        expect(instance.json_attributes).to be_blank

        instance.save!
        instance.reload

        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("_store_key" => "X")
        expect(instance.json_attributes).to be_blank
      end

      describe "multiple containers with same store key" do
        let(:klass) do
          Class.new(ActiveRecord::Base) do
            include JsonAttribute::Record
            self.table_name = "products"

            json_attribute :value, :string, store_key: "_store_key", container_attribute: :json_attributes
            json_attribute :other_value, :string, store_key: "_store_key", container_attribute: :other_attributes
          end
        end
        it "is all good" do
          instance.value = "value"
          instance.other_value = "other_value"

          expect(instance.value).to eq("value")
          expect(instance.json_attributes).to eq("_store_key" => "value")
          expect(instance.other_value).to eq("other_value")
          expect(instance.other_attributes).to eq("_store_key" => "other_value")

          instance.save!
          instance.reload

          expect(instance.value).to eq("value")
          expect(instance.json_attributes).to eq("_store_key" => "value")
          expect(instance.other_value).to eq("other_value")
          expect(instance.other_attributes).to eq("_store_key" => "other_value")
        end
        describe "with defaults" do
          let(:klass) do
            Class.new(ActiveRecord::Base) do
              include JsonAttribute::Record
              self.table_name = "products"

              json_attribute :value, :string, default: "value default", store_key: "_store_key", container_attribute: :json_attributes
              json_attribute :other_value, :string, default: "other value default", store_key: "_store_key", container_attribute: :other_attributes
            end
          end

          it "is all good" do
            expect(instance.value).to eq("value default")
            expect(instance.json_attributes).to eq("_store_key" => "value default")
            expect(instance.other_value).to eq("other value default")
            expect(instance.other_attributes).to eq("_store_key" => "other value default")
          end

          it "fills default on direct set" do
            instance.json_attributes = {}
            expect(instance.json_attributes).to eq("_store_key" => "value default")

            instance.other_attributes = {}
            expect(instance.other_attributes).to eq("_store_key" => "other value default")
          end
        end
      end
    end

    # describe "with bad attribute" do
    #   it "raises on decleration" do
    #     expect {
    #       Class.new(ActiveRecord::Base) do
    #         include JsonAttribute::Record
    #         self.table_name = "products"

    #         json_attribute :value, :string, container_attribute: :no_such_attribute
    #       end
    #     }.to raise_error(ArgumentError, /adfadf/)
    #   end
    # end

  end


end