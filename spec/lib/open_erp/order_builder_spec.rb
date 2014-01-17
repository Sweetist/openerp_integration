require 'spec_helper'

describe OpenErp::OrderBuilder do
  before(:all) do
    VCR.use_cassette('ooor') do
      Ooor.new url: 'nothing',
               database: 'nothing',
               username: 'nothing',
               password: 'nothing'
    end
  end

  let!(:payload) do
    {
      'order' => Factories.order,
      'original' => Factories.original,
      'parameters' => Factories.parameters
    }
  end

  subject do
    OpenErp::OrderBuilder.new(payload, Factories.config)
  end

  before(:each) do
    payload['order']['number'] = "2dfed1112345432111"
  end

  describe "#build!" do
    it "sets the required attributes" do
      VCR.use_cassette('build_order') do
        order = subject.build!
        order.partner_id.should be_present
        order.partner_shipping_id.should be_present
        order.shop_id.should be_present
        order.pricelist_id.should be_present
        order.picking_policy.should be_present
        order.order_policy.should be_present
        order.invoice_quantity.should == 'order'
        order.order_line.should be_present
        order.currency_id.should be_present
      end
    end
  end

  describe "#update!" do
    it "updates line items" do
      payload['original']['line_items'].each { |li|  li['quantity'] = 10.0 }
      VCR.use_cassette('build_order_update') do
        order = subject.update!
        order.order_line.first.product_uom_qty.should == 10.0
      end
    end
  end
end