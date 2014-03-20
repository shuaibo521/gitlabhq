#-------------------------------------------------------------------
#
# Copyright (C) 2013 GitLab.com - Distributed under the MIT Expat License
#
#-------------------------------------------------------------------

module Gitlab
  module LDAP
    class Group
      def self.find_by_cn(cn, adapter=nil)
        adapter ||= Gitlab::LDAP::Adapter.new
        adapter.group(cn)
      end

      def initialize(entry, adapter=nil)
        Rails.logger.debug { "Instantiating #{self.class.name} with LDIF:\n#{entry.to_ldif}" }
        @entry = entry
        @adapter = adapter
      end

      def cn
        entry.cn.first
      end

      def name
        cn
      end

      def path
        name.parameterize
      end

      def memberuid?
        entry.respond_to? :memberuid
      end

      def member_uids
        entry.memberuid
      end

      def has_member?(user)
        if memberuid?
          member_uids.include?(user.uid)
        else
          member_dns.include?(user.dn)
        end
      end

      def member_dns
        if entry.respond_to? :member
          entry.member
        elsif entry.respond_to? :uniquemember
          entry.uniquemember
        elsif entry.respond_to? :memberof
          entry.memberof
        else
          Rails.logger.warn("Could not find member DNs for LDAP group #{entry.inspect}")
          []
        end
      end

      private

      def entry
        @entry
      end

      def adapter
        @adapter ||= Gitlab::LDAP::Adapter.new
      end
    end
  end
end
