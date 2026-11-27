"""Exercise Xcode's WuMind gateway validation without making network requests."""
import unittest

from validate_wumind_gateway_build import validate


class BuildGatewayTests(unittest.TestCase):
    production = "https://release.fixture.edu/service"
    testing = "https://staging.fixture.edu/service"

    def validate_build(self, config, selected, production=None, testing=None):
        validate({
            "CONFIGURATION": config,
            "WUMIND_PRODUCTION_GATEWAY_URL": self.production if production is None else production,
            "WUMIND_TEST_GATEWAY_URL": self.testing if testing is None else testing,
            "WUMIND_BUILD_GATEWAY_URL": selected,
        })

    def test_each_build_only_accepts_its_own_address(self):
        for config, correct, other in [
            ("Debug", self.testing, self.production),
            ("Testing", self.testing, self.production),
            ("Release", self.production, self.testing),
        ]:
            with self.subTest(config=config):
                self.validate_build(config, correct)
                with self.assertRaises(ValueError):
                    self.validate_build(config, other)

    def test_release_rejects_shared_endpoint_even_when_written_differently(self):
        with self.assertRaises(ValueError):
            self.validate_build("Release", self.production, testing="https://RELEASE.fixture.edu:443/service/")

    def test_unconfirmed_release_remains_empty(self):
        self.validate_build("Release", "", production="")
        with self.assertRaises(ValueError):
            self.validate_build("Release", self.testing, production="")

    def test_invalid_operator_input_never_becomes_a_release_endpoint(self):
        invalid = ["http://release.fixture.edu", "https://staging.fixture.edu", "https://api.example.org",
                   "https://dash.cloudflare.com/profile/edit", "https://release.fixture.edu/service?auth=value"]
        for address in invalid:
            with self.subTest(address=address), self.assertRaises(ValueError):
                self.validate_build("Release", address, production=address)


if __name__ == "__main__":
    unittest.main()
