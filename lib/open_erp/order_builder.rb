module OpenErp
  class OrderBuilder
    attr_reader :payload, :config

    def initialize(payload, config)
      @payload = payload
      @config  = config
    end


    def build!
      raise OpenErpEndpointError, "All products in the order must exist on OpenERP!" unless validate_line_items?

      order = SaleOrder.new({
        name: "Spree Order #{payload['order']['number']}",
        date_order: Time.parse(payload['order']['updated_at']).strftime('%Y-%m-%e'),
        state: "done",
        invoice_quantity: "order"
      })

      set_picking_policy(order, config['shipping_policy'])
      set_order_policy(order, config['invoice_policy'])
      set_currency(order, payload['order']['currency'])
      set_customer(order, payload['order']['email'])
      order.shipped = payload['order']['status'] == 'complete' ? true : false
      order.partner_invoice_id = order.partner_id
      order.partner_shipping_id = set_partner_shipping_id(payload['order']['email'], order)
      order.shop_id = SaleShop.find(id: config['openerp.shop'].to_i).first.id
      order.pricelist_id = set_pricelist(config['openerp.pricelist'])
      update_totals(order)

      order.save
      set_line_items(order)
      order.reload
    end

    def update!
      raise OpenErpEndpointError, "All products in the order must exist on OpenERP!" unless validate_line_items?
      order = find_order
      order.partner_id = set_customer(order, payload['order']['email'])
      order.partner_invoice_id = order.partner_id
      order.partner_shipping_id = set_partner_shipping_id(payload['order']['email'], order)
      order.shipped = payload['order']['status'] == 'complete' ? true : false
      update_totals(order)

      order.save
      update_line_items(order)
      order.reload
    end

    private

      def validate_line_items?
        payload['original']['line_items'].any? do |line_item|
          ProductProduct.find(name: line_item['variant']['name']).length < 1
        end ? false : true
      end

      def update_totals(order)
        order.amount_tax = payload['order']['totals']['tax'].to_f
      end

      def find_order
        order = SaleOrder.find(name: "Spree Order #{payload['order']['number']}").first
        return order if order
        raise OpenErpEndpointError, "Order #{payload['order']['number']} could not be found on OpenErp!"
      end

      def set_line_items(order)
        payload['original']['line_items'].each do |li|
          create_line(li, order)
        end
      end

      def update_line_items(order)
        payload['original']['line_items'].each do |li|
          line = order.order_line.find { |line| line.name == li['variant']['name'] }
          if line
            line.product_id = ProductProduct.find(name: li['variant']['name']).first.id
            line.product_uom_qty = li['quantity'].to_f
            line.price_unit = li['price']
            line.save
          else
            create_line(li, order)
          end
        end
      end

      def create_line(line_payload, order)
        line = SaleOrderLine.new
        line.order_id = order.id
        line.name = line_payload['variant']['name']
        line.product_id = ProductProduct.find(name: line_payload['variant']['name']).first.id
        line.product_uom_qty = line_payload['quantity'].to_f
        line.price_unit = line_payload['price']
        line.save
      end

      def set_picking_policy(order, policy)
        case policy
        when 'Deliver all products at once'
          order.picking_policy = 'one'
        else
          order.picking_policy = 'direct'
        end
      end

      def set_order_policy(order, policy)
        case policy
        when 'On Delivery Order'
          order.order_policy = 'picking'
        when 'On Demand'
          order.order_policy = 'manual'
        else
          order.order_policy = 'prepaid'
        end
      end

      def set_currency(order, currency)
        result = ResCurrency.find(name: currency)
        if result.length > 0
          order.currency_id = result.first.id
        else
          raise OpenErpEndpointError, "Order currency #{currency} does not exist on OpenERP!"
        end
      end

      def set_customer(order, email)
        result = ResPartner.find(email: email, type: 'default')
        customer = result.empty? ? OpenErp::CustomerManager.new(ResPartner.new, payload) : OpenErp::CustomerManager.new(result.first, payload)
        order.partner_id = customer.update!.id
      end

      def set_partner_shipping_id(email, order)
        result = ResPartner.find(email: email, type: 'delivery')
        if result.length > 0
          result.first.id
        else
          order.partner_id
        end
      end

      def set_pricelist(pricelist)
        result = ProductPricelist.find(name: pricelist)
        if result.length > 0
          result.first.id
        else
          raise OpenErpEndpointError, "Pricelist #{pricelist} does not exist on OpenERP!"
        end
      end
  end
end