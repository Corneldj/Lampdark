"""QA-01: the frozen survey (survey_v1.json) matches the protocol's wording item for item."""
import json
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
PROTOCOL = os.path.join(os.path.dirname(GAME), "QA", "M1 kill-test protocol.md")


class TestSurveyFrozen(unittest.TestCase):
    def test_every_item_matches_the_protocol(self):
        survey = json.load(open(os.path.join(os.path.dirname(HERE), "survey_v1.json"), encoding="utf-8"))
        self.assertEqual(survey["version"], "v1")
        if not os.path.exists(PROTOCOL):
            self.skipTest("the protocol lives in the vault, beside the repository")
        protocol = open(PROTOCOL, encoding="utf-8").read()
        self.assertIn("**Version:** v1", protocol)
        for item in survey["items"]:
            self.assertIn(f"| {item['id']} |", protocol, item["id"])
            self.assertIn(item["text"], protocol, f"{item['id']}: the protocol's wording")

    def test_the_decisive_items_cover_criteria_1_to_3(self):
        survey = json.load(open(os.path.join(os.path.dirname(HERE), "survey_v1.json"), encoding="utf-8"))
        criteria = sorted({i["criterion"] for i in survey["items"] if "criterion" in i})
        self.assertEqual(criteria, [1, 2, 3])
        for item in survey["items"]:
            if "question" in item:
                self.assertFalse(item.get("decides", True), f"{item['id']} is an arm: it never decides")


if __name__ == "__main__":
    unittest.main()
