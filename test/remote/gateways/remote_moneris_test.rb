require 'test_helper'

class MonerisRemoteTest < Test::Unit::TestCase
  def setup
    Base.mode = :test

    @gateway = MonerisGateway.new(fixtures(:moneris))
    @amount = 100
    @credit_card = credit_card('4242424242424242')
    @options = {
        :order_id => generate_unique_id,
        :customer => generate_unique_id,
        :billing_address => address
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
  end

  def test_successful_first_purchase_with_credential_on_file
    gateway = MonerisGateway.new(fixtures(:moneris).merge(cof_enabled: true))
    assert response = gateway.purchase(@amount, @credit_card, @options.merge(issuer_id: '', payment_indicator: 'C', payment_information: '0'))
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
    assert_not_empty response.params['issuer_id']
  end

  def test_successful_purchase_with_cof_enabled_and_no_cof_options
    gateway = MonerisGateway.new(fixtures(:moneris).merge(cof_enabled: true))
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
  end

  def test_successful_non_cof_purchase_with_cof_enabled_and_only_issuer_id_sent
    gateway = MonerisGateway.new(fixtures(:moneris).merge(cof_enabled: true))
    assert response = gateway.purchase(@amount, @credit_card, @options.merge(issuer_id: ''))
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
    assert_nil response.params['issuer_id']
  end

  def test_successful_subsequent_purchase_with_credential_on_file
    gateway = MonerisGateway.new(fixtures(:moneris).merge(cof_enabled: true))
    assert response = gateway.authorize(
      @amount,
      @credit_card,
      @options.merge(
        issuer_id: '',
        payment_indicator: 'C',
        payment_information: '0'
      )
    )
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?

    assert response2 = gateway.purchase(
      @amount,
      @credit_card,
      @options.merge(
        order_id: response.authorization,
        issuer_id: response.params['issuer_id'],
        payment_indicator: 'U',
        payment_information: '2'
      )
    )
    assert_success response2
    assert_equal 'Approved', response2.message
    assert_false response2.authorization.blank?
  end

  def test_successful_purchase_with_network_tokenization
    @credit_card = network_tokenization_credit_card(
      '4242424242424242',
      payment_cryptogram: 'BwABB4JRdgAAAAAAiFF2AAAAAAA=',
      verification_value: nil
    )
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
  end

  def test_successful_purchase_with_network_tokenization_apple_pay_source
    @credit_card = network_tokenization_credit_card(
      '4242424242424242',
      payment_cryptogram: 'BwABB4JRdgAAAAAAiFF2AAAAAAA=',
      verification_value: nil,
      source: :apple_pay
    )
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
  end

  def test_successful_authorization
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_false response.authorization.blank?
  end

  def test_failed_authorization
    response = @gateway.authorize(105, @credit_card, @options)
    assert_failure response
  end

  def test_successful_authorization_and_capture
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert response.authorization

    response = @gateway.capture(@amount, response.authorization)
    assert_success response
  end

  def test_successful_authorization_and_capture_and_void
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert response.authorization

    response = @gateway.capture(@amount, response.authorization)
    assert_success response

    void = @gateway.void(response.authorization, :purchasecorrection => true)
    assert_success void
  end

  def test_successful_authorization_and_void
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert response.authorization

    void = @gateway.void(response.authorization)
    assert_success void
  end

  def test_successful_authorization_with_network_tokenization
    @credit_card = network_tokenization_credit_card(
      '4242424242424242',
      payment_cryptogram: 'BwABB4JRdgAAAAAAiFF2AAAAAAA=',
      verification_value: nil
    )
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
  end

  def test_successful_purchase_and_void
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    void = @gateway.void(purchase.authorization, :purchasecorrection => true)
    assert_success void
  end

  def test_failed_purchase_and_void
    purchase = @gateway.purchase(101, @credit_card, @options)
    assert_failure purchase

    void = @gateway.void(purchase.authorization)
    assert_failure void
  end

  def test_successful_purchase_and_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    refund = @gateway.refund(@amount, purchase.authorization)
    assert_success refund
  end

  def test_failed_purchase_from_error
    assert response = @gateway.purchase(150, @credit_card, @options)
    assert_failure response
    assert_equal 'Declined', response.message
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match 'Approved', response.message
  end

  def test_successful_store
    assert response = @gateway.store(@credit_card)
    assert_success response
    assert_equal 'Successfully registered cc details', response.message
    assert response.params['data_key'].present?
    @data_key = response.params['data_key']
  end

  def test_successful_unstore
    test_successful_store
    assert response = @gateway.unstore(@data_key)
    assert_success response
    assert_equal 'Successfully deleted cc details', response.message
    assert response.params['data_key'].present?
  end

  def test_update
    test_successful_store
    assert response = @gateway.update(@data_key, @credit_card)
    assert_success response
    assert_equal 'Successfully updated cc details', response.message
    assert response.params['data_key'].present?
  end

  def test_successful_purchase_with_vault
    test_successful_store
    assert response = @gateway.purchase(@amount, @data_key, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_false response.authorization.blank?
  end

  def test_successful_authorization_with_vault
    test_successful_store
    assert response = @gateway.authorize(@amount, @data_key, @options)
    assert_success response
    assert_false response.authorization.blank?
  end

  def test_failed_authorization_with_vault
    test_successful_store
    response = @gateway.authorize(105, @data_key, @options)
    assert_failure response
  end

  def test_cvv_match_when_not_enabled
    assert response = @gateway.purchase(1039, @credit_card, @options)
    assert_success response
    assert_equal({'code' => nil, 'message' => nil}, response.cvv_result)
  end

  def test_cvv_no_match_when_not_enabled
    assert response = @gateway.purchase(1053, @credit_card, @options)
    assert_success response
    assert_equal({'code' => nil, 'message' => nil}, response.cvv_result)
  end

  def test_cvv_match_when_enabled
    gateway = MonerisGateway.new(fixtures(:moneris).merge(cvv_enabled: true))
    assert response = gateway.purchase(1039, @credit_card, @options)
    assert_success response
    assert_equal({'code' => 'M', 'message' => 'CVV matches'}, response.cvv_result)
  end

  def test_avs_result_valid_when_enabled
    gateway = MonerisGateway.new(fixtures(:moneris).merge(avs_enabled: true))

    assert response = gateway.purchase(1010, @credit_card, @options)
    assert_success response
    assert_equal(response.avs_result, {
        'code' => 'A',
        'message' => 'Street address matches, but 5-digit and 9-digit postal code do not match.',
        'street_match' => 'Y',
        'postal_match' => 'N'
    })
  end

  def test_avs_result_nil_when_address_absent
    gateway = MonerisGateway.new(fixtures(:moneris).merge(avs_enabled: true))

    assert response = gateway.purchase(1010, @credit_card, @options.tap { |x| x.delete(:billing_address) })
    assert_success response
    assert_equal(response.avs_result, {
        'code' => nil,
        'message' => nil,
        'street_match' => nil,
        'postal_match' => nil
    })
  end

  def test_avs_result_nil_when_efraud_disabled
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal(response.avs_result, {
        'code' => nil,
        'message' => nil,
        'street_match' => nil,
        'postal_match' => nil
    })
  end

  def test_purchase_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(credit_card.number, transcript)
    assert_scrubbed(credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:password], transcript)
  end
end
