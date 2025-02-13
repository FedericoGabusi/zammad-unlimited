# Copyright (C) 2012-2023 Zammad Foundation, https://zammad-foundation.org/

class SMIMECertificate < ApplicationModel
  default_scope { order(not_after_at: :desc, not_before_at: :desc, id: :desc) }

  validates :fingerprint, uniqueness: { case_sensitive: true }

  def self.parts(raw)
    raw.scan(%r{-----BEGIN[^-]+-----.+?-----END[^-]+-----}m)
  end

  def self.create_private_keys(raw, secret)
    parts(raw).select { |part| part.include?('PRIVATE KEY') }.each do |part|
      private_key = OpenSSL::PKey.read(part, secret)
      modulus     = private_key.public_key.n.to_s(16)
      certificate = find_by(modulus: modulus)

      raise Exceptions::UnprocessableEntity, __('The certificate for this private key could not be found.') if !certificate

      certificate.update!(private_key: part, private_key_secret: secret)
    end
  end

  def self.create_certificates(raw)
    parts(raw).select { |part| part.include?('CERTIFICATE') }.each_with_object([]) do |part, result|
      result << create!(public_key: part)
    end
  end

  def self.parse(raw)
    OpenSSL::X509::Certificate.new(raw.gsub(%r{(?:TRUSTED\s)?(CERTIFICATE---)}, '\1'))
  end

  # Search for the certificate of the given sender email address
  #
  # @example
  #  certificate = SMIMECertificates.for_sender_email_address('some1@example.com')
  #  # => #<SMIMECertificate:0x00007fdd4e27eec0...
  #
  # @return [SMIMECertificate, nil] The found certificate record or nil
  def self.for_sender_email_address(address)
    downcased_address = address.downcase
    where.not(private_key: nil).all.as_batches do |certificate|
      next if certificate.key_usage_prohibits?('Digital Signature') # rubocop:disable Zammad/DetectTranslatableString

      return certificate if certificate.email_addresses.include?(downcased_address)
    end
  end

  # Search for certificates of the given recipients email addresses
  #
  # @example
  #  certificates = SMIMECertificates.for_recipient_email_addresses!(['some1@example.com', 'some2@example.com'])
  #  # => [#<SMIMECertificate:0x00007fdd4e27eec0...
  #
  # @raise [ActiveRecord::RecordNotFound] if there are recipients for which no certificate could be found
  #
  # @return [Array<SMIMECertificate>] The found certificate records
  def self.for_recipient_email_addresses!(addresses)
    certificates        = []
    remaining_addresses = addresses.map(&:downcase)
    all.as_batches do |certificate|

      # intersection of both lists
      certificate_for = certificate.email_addresses & remaining_addresses
      next if certificate_for.blank?
      next if certificate.key_usage_prohibits?('Key Encipherment') # rubocop:disable Zammad/DetectTranslatableString

      certificates.push(certificate)

      # subtract found recipient(s)
      remaining_addresses -= certificate_for

      # end loop if no addresses are remaining
      break if remaining_addresses.blank?
    end

    return certificates if remaining_addresses.blank?

    raise ActiveRecord::RecordNotFound, "Can't find S/MIME encryption certificates for: #{remaining_addresses.join(', ')}"
  end

  def key_usage_prohibits?(usage_type)
    # Respect restriction of keyUsage extension, if present.
    # See https://datatracker.ietf.org/doc/html/rfc5280#section-4.2.1.3 and https://www.gradenegger.eu/?p=9563
    parsed.extensions.find { |ext| ext.oid == 'keyUsage' }&.value&.exclude?(usage_type)
  end

  def public_key=(string)
    cert = self.class.parse(string)

    self.subject       = cert.subject
    self.doc_hash      = cert.subject.hash.to_s(16)
    self.fingerprint   = OpenSSL::Digest.new('SHA1', cert.to_der).to_s
    self.modulus       = cert.public_key.n.to_s(16)
    self.not_before_at = cert.not_before
    self.not_after_at  = cert.not_after
    self.raw           = cert.to_s
  end

  def parsed
    @parsed ||= self.class.parse(raw)
  end

  def email_addresses
    @email_addresses ||= begin
      subject_alt_name = parsed.extensions.detect { |extension| extension.oid == 'subjectAltName' }
      if subject_alt_name.blank?
        Rails.logger.warn <<~TEXT.squish
          SMIMECertificate with ID #{id} has no subjectAltName
          extension and therefore no email addresses assigned.
          This makes it useless in terms of S/MIME. Please check.
        TEXT

        []
      else
        email_addresses_from_subject_alt_name(subject_alt_name)
      end
    end
  end

  def expired?
    !Time.zone.now.between?(not_before_at, not_after_at)
  end

  private

  def email_addresses_from_subject_alt_name(subject_alt_name)
    # ["IP Address:192.168.7.23", "IP Address:192.168.7.42", "email:jd@example.com", "email:John.Doe@example.com", "dirName:dir_sect"]
    entries = subject_alt_name.value.split(%r{,\s?})

    entries.each_with_object([]) do |entry, result|
      # ["email:jd@example.com", "email:John.Doe@example.com"]
      identifier, email_address = entry.split(':').map(&:downcase)

      # See: https://stackoverflow.com/a/20671427
      # ["email:jd@example.com", "emailAddress:jd@example.com", "rfc822:jd@example.com", "rfc822Name:jd@example.com"]
      next if identifier.exclude?('email') && identifier.exclude?('rfc822')

      if !EmailAddressValidation.new(email_address).valid?
        Rails.logger.warn <<~TEXT.squish
          SMIMECertificate with ID #{id} has the malformed email address "#{email_address}"
          stored as "#{identifier}" in the subjectAltName extension.
          This makes it useless in terms of S/MIME. Please check.
        TEXT

        next
      end

      result.push(email_address)
    end
  end
end
