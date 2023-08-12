# typed: true
# frozen_string_literal: true

require 'test_helper'

module Packwerk
  module Privacy
    class CheckerTest < Minitest::Test
      extend T::Sig
      include FactoryHelper
      include RailsApplicationFixtureHelper

      setup do
        setup_application_fixture
      end

      teardown do
        teardown_application_fixture
      end

      test 'ignores if destination package is not enforcing' do
        destination_package = Packwerk::Package.new(
          name: 'destination_package',
          config: { 'enforce_privacy' => false, 'private_constants' => ['::SomeName'] }
        )
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package)

        refute checker.invalid_reference?(reference)
      end

      test 'ignores if destination package is only enforcing for other constants' do
        destination_package = Packwerk::Package.new(
          name: 'destination_package',
          config: { 'enforce_privacy' => true, 'private_constants' => ['::SomeOtherConstant'] }
        )
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package)

        refute checker.invalid_reference?(reference)
      end

      test 'complains about private constant if enforcing privacy for everything' do
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => true })
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package)

        assert checker.invalid_reference?(reference)
      end

      test 'does not complain about private constant if it is an ignored_private_constant when using enforce_privacy' do
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'ignored_private_constants' => ['::SomeName'], 'enforce_privacy' => true })
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package)

        refute checker.invalid_reference?(reference)
      end

      test 'complains about private constant if enforcing for specific constants' do
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => true, 'private_constants' => ['::SomeName'] })
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package)

        assert checker.invalid_reference?(reference)
      end

      test 'complains about nested constant if enforcing for specific constants' do
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => true, 'private_constants' => ['::SomeName'] })
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package, constant_name: '::SomeName::Nested')

        assert checker.invalid_reference?(reference)
      end

      test 'ignores constant that starts like enforced constant' do
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => true, 'private_constants' => ['::SomeName'] })
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package, constant_name: '::SomeNameButNotQuite')

        refute checker.invalid_reference?(reference)
      end

      test 'ignores public constant even if enforcing privacy for everything' do
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => true })
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package, constant_location: 'destination_package/app/public/')

        refute checker.invalid_reference?(reference)
      end

      test 'only checks the package TODO file for private constants' do
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => true, 'private_constants' => ['::SomeName'] })
        checker = privacy_checker
        reference = build_reference(destination_package: destination_package)

        checker.invalid_reference?(reference)
      end

      test 'provides a useful message' do
        assert_equal privacy_checker.message(build_reference), <<~MSG.chomp
          Privacy violation: '::SomeName' is private to 'components/destination' but referenced from 'components/source'.
          Is there a public entrypoint in 'components/destination/app/public/' that you can use instead?

          Inference details: this is a reference to ::SomeName which seems to be defined in some/location.rb.
          To receive help interpreting or resolving this error message, see: https://github.com/Shopify/packwerk/blob/main/TROUBLESHOOT.md#Troubleshooting-violations
        MSG
      end

      test 'does not report any violation as strict in non strict mode' do
        use_template(:minimal)

        source_package = Packwerk::Package.new(name: 'components/source', config: { 'enforce_privacy' => true })
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => true })
        checker = privacy_checker

        write_app_file('components/source/package_todo.yml', <<~YML.strip)
          ---
          "destination_package":
            "::SomeName":
              violations:
              - privacy
              files:
              - components/source/some/path.rb
        YML

        known_offense = Packwerk::ReferenceOffense.new(
          reference: build_reference(source_package: source_package, destination_package: destination_package, path: 'components/source/some/path.rb'),
          violation_type: Packwerk::Privacy::Checker::VIOLATION_TYPE,
          message: 'some message'
        )
        unknown_offense = Packwerk::ReferenceOffense.new(
          reference: build_reference(destination_package: destination_package),
          violation_type: Packwerk::Privacy::Checker::VIOLATION_TYPE,
          message: 'some message'
        )

        refute checker.strict_mode_violation?(bundle_offense_with_package_todo(known_offense))
        refute checker.strict_mode_violation?(bundle_offense_with_package_todo(unknown_offense))
      end

      test 'reports any violation as strict in strict mode' do
        use_template(:minimal)

        source_package = Packwerk::Package.new(name: 'components/source', config: { 'enforce_privacy' => 'strict' })
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => 'strict' })
        checker = privacy_checker

        write_app_file('components/source/package_todo.yml', <<~YML.strip)
          ---
          "destination_package":
            "::SomeName":
              violations:
              - privacy
              files:
              - components/source/some/path.rb
        YML

        known_offense = Packwerk::ReferenceOffense.new(
          reference: build_reference(source_package: source_package, destination_package: destination_package, path: 'components/source/some/path.rb'),
          violation_type: Packwerk::Privacy::Checker::VIOLATION_TYPE,
          message: 'some message'
        )
        unknown_offense = Packwerk::ReferenceOffense.new(
          reference: build_reference(destination_package: destination_package),
          violation_type: Packwerk::Privacy::Checker::VIOLATION_TYPE,
          message: 'some message'
        )

        assert checker.strict_mode_violation?(bundle_offense_with_package_todo(known_offense))
        assert checker.strict_mode_violation?(bundle_offense_with_package_todo(unknown_offense))
      end

      test 'only reports unlisted violations as strict in strict_for_new mode' do
        use_template(:minimal)

        source_package = Packwerk::Package.new(name: 'components/source', config: { 'enforce_privacy' => 'strict_for_new' })
        destination_package = Packwerk::Package.new(name: 'destination_package', config: { 'enforce_privacy' => 'strict_for_new' })
        checker = privacy_checker

        write_app_file('components/source/package_todo.yml', <<~YML.strip)
          ---
          "destination_package":
            "::SomeName":
              violations:
              - privacy
              files:
              - components/source/some/path.rb
        YML

        known_offense = Packwerk::ReferenceOffense.new(
          reference: build_reference(source_package: source_package, destination_package: destination_package, path: 'components/source/some/path.rb'),
          violation_type: Packwerk::Privacy::Checker::VIOLATION_TYPE,
          message: 'some message'
        )
        unknown_offense = Packwerk::ReferenceOffense.new(
          reference: build_reference(destination_package: destination_package),
          violation_type: Packwerk::Privacy::Checker::VIOLATION_TYPE,
          message: 'some message'
        )

        refute checker.strict_mode_violation?(bundle_offense_with_package_todo(known_offense))
        assert checker.strict_mode_violation?(bundle_offense_with_package_todo(unknown_offense))
      end

      private

      sig { returns(Checker) }
      def privacy_checker
        Privacy::Checker.new
      end

      sig { params(offense: ReferenceOffense).returns(Packwerk::ReferenceOffenseWithPackageTodo) }
      def bundle_offense_with_package_todo(offense)
        Packwerk::ReferenceOffenseWithPackageTodo.from_reference_offense(offense, package_todo: package_todo_for(offense.reference.package))
      end

      sig { params(package: Packwerk::Package).returns(Packwerk::PackageTodo) }
      def package_todo_for(package)
        Packwerk::PackageTodo.new(
          package,
          package_todo_file_for(package)
        )
      end

      sig { params(package: Packwerk::Package).returns(String) }
      def package_todo_file_for(package)
        File.join(Packwerk::Configuration.from_path.root_path, package.name, 'package_todo.yml')
      end
    end
  end
end
