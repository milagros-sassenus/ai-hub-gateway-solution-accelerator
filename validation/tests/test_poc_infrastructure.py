"""Compile infrastructure and check PoC resource boundaries and reporting exclusions."""

import ipaddress
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
INFRA = ROOT / "bicep" / "infra"


def resources(template):
    collection = template.get("resources", {})
    return list(collection.values()) if isinstance(collection, dict) else collection


def named_resource(template, name):
    return next(resource for resource in resources(template) if resource["name"] == name)


class PocInfrastructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        az = shutil.which("az")
        if not az:
            raise unittest.SkipTest("Azure CLI with Bicep is required for compilation tests")
        cls.directory = tempfile.TemporaryDirectory(prefix="citadel-infra-tests-")
        cls.addClassCleanup(cls.directory.cleanup)
        directory = Path(cls.directory.name)
        cls.lab_source_directory = tempfile.TemporaryDirectory(prefix=".prod-lab-tests-", dir=INFRA)
        cls.addClassCleanup(cls.lab_source_directory.cleanup)
        lab_source = Path(cls.lab_source_directory.name) / "lab.bicepparam"
        prod_source = (INFRA / "apim-gateway-upgrade" / "main.parameters.prod.bicepparam").read_text(
            encoding="utf-8"
        )
        selector = "var useExistingLabFoundry = false"
        if prod_source.count(selector) != 1:
            raise AssertionError("Expected one explicit Foundry lab selector in production parameters")
        lab_source.write_text(
            prod_source.replace(selector, "var useExistingLabFoundry = true"), encoding="utf-8",
        )
        for action, source, output in (
            ("build", INFRA / "main.bicep", directory / "main.json"),
            (
                "build-params",
                INFRA / "apim-gateway-upgrade" / "main.parameters.dev.bicepparam",
                directory / "parameters.json",
            ),
            (
                "build-params",
                INFRA / "apim-gateway-upgrade" / "main.parameters.prod.bicepparam",
                directory / "prod-parameters.json",
            ),
            ("build", INFRA / "apim-gateway-upgrade" / "main.bicep", directory / "upgrade.json"),
            ("build-params", INFRA / "main.bicepparam", directory / "defaults.json"),
            ("build-params", lab_source, directory / "lab-parameters.json"),
            (
                "build",
                INFRA / "apim-gateway-upgrade" / "network-prerequisites.bicep",
                directory / "network.json",
            ),
        ):
            result = subprocess.run(
                [az, "bicep", action, "--file", str(source), "--outfile", str(output)],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                cwd=ROOT, timeout=180, check=False,
            )
            if result.returncode:
                raise AssertionError(f"Bicep {action} failed:\n{result.stdout}\n{result.stderr}")
        cls.main = json.loads((directory / "main.json").read_text(encoding="utf-8-sig"))
        cls.network = json.loads((directory / "network.json").read_text(encoding="utf-8-sig"))
        cls.parameters = {
            key: value["value"]
            for key, value in json.loads(
                (directory / "parameters.json").read_text(encoding="utf-8-sig")
            )["parameters"].items()
        }
        cls.prod_parameters = {
            key: value["value"]
            for key, value in json.loads(
                (directory / "prod-parameters.json").read_text(encoding="utf-8-sig")
            )["parameters"].items()
        }
        cls.lab_parameters = {
            key: value["value"]
            for key, value in json.loads(
                (directory / "lab-parameters.json").read_text(encoding="utf-8-sig")
            )["parameters"].items()
        }
        cls.hub = next(
            resource for resource in resources(cls.main)
            if resource["type"] == "Microsoft.Resources/deployments"
        )["properties"]["template"]

    def test_dev_excludes_ingestion_and_reporting_without_changing_defaults(self):
        self.assertIs(self.parameters["enableUsageReporting"], False)
        self.assertIs(self.parameters["createAppInsightsDashboards"], False)
        for template in (self.main, self.hub):
            self.assertIs(template["parameters"]["enableUsageReporting"]["defaultValue"], True)
        hub_module = next(
            r for r in resources(self.main) if r["type"] == "Microsoft.Resources/deployments"
        )
        self.assertEqual(
            hub_module["properties"]["parameters"]["enableUsageReporting"]["value"],
            "[parameters('enableUsageReporting')]",
        )
        for name in (
            "logicapp-usage-managed-identity", "event-hub", "cosmos-db",
            "logicapp-usage-cosmos-sql-role", "storage", "usageLogicApp",
        ):
            with self.subTest(module=name):
                self.assertEqual(
                    named_resource(self.hub, name)["condition"],
                    "[parameters('enableUsageReporting')]",
                )
        for name in ("COSMOS_DB_ACCOUNT_NAME", "EVENT_HUB_NAME"):
            expression = self.hub["outputs"][name]["value"]
            self.assertTrue(expression.startswith("[if(parameters('enableUsageReporting'), "))
            self.assertTrue(expression.endswith(", '')]"))

    def test_gateway_preserves_diagnostics_and_pii_without_event_hub_loggers(self):
        module = named_resource(self.hub, "apim")
        self.assertNotIn("condition", module)
        parameters = module["properties"]["parameters"]
        self.assertEqual(
            parameters["enableUsageReporting"]["value"], "[parameters('enableUsageReporting')]",
        )
        for name in ("eventHubName", "eventHubEndpoint", "eventHubPIIName", "eventHubPIIEndpoint"):
            output = "eventHubEndpoint" if name == "eventHubPIIEndpoint" else name
            self.assertEqual(
                parameters[name],
                "[if(parameters('enableUsageReporting'), "
                f"createObject('value', reference('eventHub').outputs.{output}.value), "
                "createObject('value', ''))]",
            )
        template = module["properties"]["template"]
        loggers = [
            r for r in resources(template)
            if r["type"] == "Microsoft.ApiManagement/service/loggers"
            and r["properties"]["loggerType"] == "azureEventHub"
        ]
        self.assertEqual(len(loggers), 2)
        self.assertEqual(
            loggers[0]["condition"], "[parameters('enableUsageReporting')]",
        )
        for logger in loggers:
            self.assertIn("parameters('enableUsageReporting')", logger["condition"])
        self.assertTrue(any(
            r["type"] == "Microsoft.ApiManagement/service/loggers"
            and r["properties"]["loggerType"] == "applicationInsights"
            and "condition" not in r
            for r in resources(template)
        ))
        self.assertTrue(any(
            r["type"] == "Microsoft.Insights/diagnosticSettings" and "condition" not in r
            for r in resources(template)
        ))
        self.assertIs(self.parameters["enableAIGatewayPiiRedaction"], True)
        fragments = named_resource(template, "apim-policy-fragments")
        self.assertEqual(
            fragments["properties"]["parameters"]["enableUsageReporting"]["value"],
            "[parameters('enableUsageReporting')]",
        )
        fragment_template = fragments["properties"]["template"]
        values = [
            r["properties"]["value"] for r in resources(fragment_template)
            if r["type"] == "Microsoft.ApiManagement/service/policyFragments"
        ]
        event_hub_xml = {
            f"variables('{name}')": value
            for name, value in fragment_template["variables"].items()
            if isinstance(value, str) and "<log-to-eventhub" in value
        }
        self.assertEqual(len(event_hub_xml), 2)
        event_hub_fragments = [
            value for value in values
            if any(reference in value for reference in event_hub_xml)
        ]
        self.assertEqual(len(event_hub_fragments), 2)
        for value in event_hub_fragments:
            self.assertTrue(value.startswith("[if(parameters('enableUsageReporting'), "))
            self.assertTrue(value.endswith(", '<fragment />')]"))
        anonymization = next(
            r for r in resources(fragment_template) if "'pii-anonymization'" in r["name"]
        )
        self.assertNotIn("enableUsageReporting", anonymization["properties"]["value"])

    def test_standard_workflow_requires_https_and_uses_valid_role_definition_scopes(self):
        template = named_resource(self.hub, "usageLogicApp")["properties"]["template"]
        site = next(r for r in resources(template) if r["type"] == "Microsoft.Web/sites")
        self.assertIs(site["properties"]["httpsOnly"], True)
        cosmos_role = next(
            r for r in resources(template)
            if r["type"] == "Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments"
        )
        self.assertTrue(
            cosmos_role["properties"]["roleDefinitionId"].startswith("[format('{0}/sqlRoleDefinitions/"),
        )
        for variable in ("eventHubsDataOwnerRoleDefinitionId", "azureMonitorLogsRoleDefinitionId"):
            self.assertTrue(template["variables"][variable].startswith("[subscriptionResourceId("))

    def test_dashboard_deployments_are_scoped_to_each_dashboard_name(self):
        monitoring = named_resource(self.hub, "monitoring")["properties"]["template"]
        for component in ("application-insights", "func-application-insights", "foundry-application-insights"):
            with self.subTest(component=component):
                template = named_resource(monitoring, component)["properties"]["template"]
                dashboard = next(
                    resource for resource in resources(template)
                    if resource["type"] == "Microsoft.Resources/deployments"
                )
                self.assertIn("parameters('dashboardName')", dashboard["name"])
                self.assertEqual(dashboard["condition"], "[parameters('createDashboard')]")
                self.assertEqual(
                    dashboard["properties"]["parameters"]["name"]["value"],
                    "[parameters('dashboardName')]",
                )

    def test_dedicated_monitoring_and_event_sender_role_follow_reporting_flag(self):
        monitoring = named_resource(self.hub, "monitoring")
        self.assertEqual(
            monitoring["properties"]["parameters"]["enableUsageReporting"]["value"],
            "[parameters('enableUsageReporting')]",
        )
        template = monitoring["properties"]["template"]
        self.assertEqual(
            named_resource(template, "func-application-insights")["condition"],
            "[parameters('enableUsageReporting')]",
        )
        self.assertNotIn("condition", named_resource(template, "application-insights"))
        for name in (
            "funcApplicationInsightsName", "funcApplicationInsightsConnectionString",
            "funcApplicationInsightsInstrumentationKey",
        ):
            expression = template["outputs"][name]["value"]
            self.assertTrue(expression.startswith("[if(parameters('enableUsageReporting'), "))
            self.assertTrue(expression.endswith(", '')]"))
        identity = named_resource(self.hub, "apim-managed-identity")
        self.assertEqual(
            identity["properties"]["parameters"]["enableUsageReporting"]["value"],
            "[parameters('enableUsageReporting')]",
        )
        sender = next(
            r for r in resources(identity["properties"]["template"])
            if "eventHubsDataSenderRoleDefinitionId" in r.get("properties", {}).get("roleDefinitionId", "")
        )
        self.assertEqual(sender["condition"], "[parameters('enableUsageReporting')]")

    def test_reporting_subnet_and_dns_are_optional_in_both_network_modes(self):
        for name in ("vnet", "vnetExisting", "existing-vnet-subnets"):
            module = named_resource(self.hub, name)
            self.assertEqual(
                module["properties"]["parameters"]["enableFunctionAppSubnet"]["value"],
                "[parameters('enableUsageReporting')]",
            )
        existing = named_resource(self.hub, "existing-vnet-subnets")["properties"]["template"]
        self.assertEqual(
            named_resource(existing, "logic-app-subnet")["condition"],
            "[parameters('enableFunctionAppSubnet')]",
        )
        new = named_resource(self.hub, "vnet")["properties"]["template"]
        function_subnet = next(
            r for r in resources(new)
            if r["type"] == "Microsoft.Network/virtualNetworks/subnets"
            and "functionAppSubnetName" in r["name"]
        )
        self.assertEqual(function_subnet["condition"], "[parameters('enableFunctionAppSubnet')]")
        nsg = next(
            r for r in resources(new)
            if r["type"] == "Microsoft.Network/networkSecurityGroups"
            and "functionAppNsgName" in r["name"]
        )
        self.assertEqual(nsg["condition"], "[parameters('enableFunctionAppSubnet')]")
        dns = self.hub["variables"]["privateDnsZoneNames"]
        self.assertIn("if(parameters('enableUsageReporting'), ", dns)
        for name in (
            "eventHubPrivateDnsZoneName", "cosmosDbPrivateDnsZoneName",
            "storageBlobPrivateDnsZoneName", "storageFilePrivateDnsZoneName",
            "storageTablePrivateDnsZoneName", "storageQueuePrivateDnsZoneName",
        ):
            self.assertNotIn(f"[variables('{name}')]", self.hub["variables"]["baseDnsZoneNames"])
            self.assertIn(f"variables('{name}')", dns)
        self.assertIn(
            "parameters('enableUsageReporting')",
            self.hub["variables"]["createLogicAppDnsZone"],
        )

    def test_poc_uses_current_subscription_and_brazil_south(self):
        self.assertEqual(self.parameters["resourceGroupName"], "rg-sfc-ai-landing-zone")
        self.assertEqual(self.parameters["location"], "brazilsouth")
        for template in (self.main, self.hub):
            self.assertIn("brazilsouth", template["parameters"]["location"]["allowedValues"])
        self.assertNotIn("subscriptionId", self.parameters["existingAiFoundry"])
        existing = named_resource(self.hub, "existing-ai-foundry")
        self.assertIn("subscription().subscriptionId", existing["subscriptionId"])
        self.assertEqual(self.parameters["dnsSubscriptionId"], "")

    def test_existing_foundry_preserves_default_and_byo_boundaries(self):
        self.assertIs(self.main["parameters"]["existingAiFoundry"]["nullable"], True)
        self.assertNotIn("defaultValue", self.main["parameters"]["existingAiFoundry"])
        new = named_resource(self.hub, "ai-foundry")
        existing = named_resource(self.hub, "existing-ai-foundry")
        self.assertEqual(new["condition"], "[equals(parameters('existingAiFoundry'), null())]")
        self.assertEqual(existing["condition"], "[not(equals(parameters('existingAiFoundry'), null()))]")
        self.assertIs(existing["properties"]["parameters"]["createNew"]["value"], False)
        self.assertIs(existing["properties"]["parameters"]["deployModels"]["value"], False)
        self.assertEqual(self.parameters["aiFoundryInstances"], [])
        self.assertEqual(self.parameters["aiFoundryModelsConfig"], [])
        self.assertEqual(
            named_resource(self.hub, "key-vault-foundry-rbac")["condition"], new["condition"],
        )
        self.assertEqual(
            self.hub["variables"]["llmBackendConfig"],
            "[if(not(equals(parameters('existingAiFoundry'), null())), "
            "parameters('existingLlmBackendConfig'), variables('generatedLlmBackendConfig'))]",
        )
        byo = existing["properties"]["template"]
        account = next(r for r in resources(byo) if r["type"] == "Microsoft.CognitiveServices/accounts")
        self.assertEqual(account["condition"], "[parameters('createNew')]")
        project = next(
            r for r in resources(byo)
            if r["type"] == "Microsoft.CognitiveServices/accounts/projects"
        )
        self.assertEqual(project["condition"], "[parameters('createNew')]")
        self.assertIn("existingFoundry", named_resource(self.hub, "apim")["dependsOn"])

    def test_external_vnet_and_dns_are_not_provisioned(self):
        self.assertIs(self.parameters["useExistingVnet"], True)
        self.assertIs(self.parameters["manageExistingVnetSubnets"], True)
        self.assertEqual(self.parameters["dnsZoneRG"], "rg-bancoagrario-lab")
        self.assertIs(self.hub["parameters"]["manageExistingVnetSubnets"]["defaultValue"], False)
        for key in ("vnet", "dnsDeployment"):
            self.assertEqual(
                self.hub["resources"][key]["condition"], "[not(parameters('useExistingVnet'))]",
            )
        subnet_module = named_resource(self.hub, "existing-vnet-subnets")
        self.assertEqual(
            subnet_module["condition"],
            "[and(parameters('useExistingVnet'), parameters('manageExistingVnetSubnets'))]",
        )
        self.assertIn("existingVnetSubnets", named_resource(self.hub, "vnetExisting")["dependsOn"])
        template = subnet_module["properties"]["template"]
        self.assertFalse(any(
            r["type"] in (
                "Microsoft.Network/virtualNetworks", "Microsoft.Network/privateDnsZones",
                "Microsoft.Network/privateDnsZones/virtualNetworkLinks",
            )
            for r in resources(template)
        ))
        subnet_modules = {
            r["name"]: r for r in resources(template)
            if r["type"] == "Microsoft.Resources/deployments"
        }
        self.assertEqual(len(subnet_modules), 4)
        self.assertTrue(subnet_modules["private-endpoint-subnet"]["dependsOn"])
        self.assertTrue(subnet_modules["logic-app-subnet"]["dependsOn"])
        delegation = subnet_modules["logic-app-subnet"]["properties"]["parameters"]["properties"]["value"]
        self.assertEqual(delegation["delegations"][0]["properties"]["serviceName"], "Microsoft.Web/serverFarms")

    def test_prod_keeps_logic_and_reserved_subnets_distinct_and_inside_vnet(self):
        parameters = self.prod_parameters
        vnet = ipaddress.ip_network(parameters["vnetAddressPrefix"])
        prefixes = [
            parameters["apimSubnetPrefix"],
            parameters["privateEndpointSubnetPrefix"],
            parameters["functionAppSubnetPrefix"],
            *(subnet["addressPrefix"] for subnet in parameters["reservedSubnets"]),
        ]
        networks = [ipaddress.ip_network(prefix) for prefix in prefixes]
        for index, subnet in enumerate(networks):
            self.assertTrue(subnet.subnet_of(vnet))
            for other in networks[index + 1:]:
                self.assertFalse(subnet.overlaps(other))
        names = [
            parameters["apimSubnetName"], parameters["privateEndpointSubnetName"],
            parameters["functionAppSubnetName"],
            *(subnet["name"] for subnet in parameters["reservedSubnets"]),
        ]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(len(parameters["reservedSubnets"]), 3)
        module = named_resource(self.hub, "existing-vnet-subnets")
        for name in ("reservedSubnets", "managePrivateEndpointSubnet", "apimFirewallIp"):
            self.assertEqual(
                module["properties"]["parameters"][name]["value"], f"[parameters('{name}')]",
            )
        template = module["properties"]["template"]
        self.assertEqual(
            named_resource(template, "private-endpoint-subnet")["condition"],
            "[parameters('managePrivateEndpointSubnet')]",
        )
        reservation = next(r for r in resources(template) if r.get("copy", {}).get("name") == "reservations")
        self.assertEqual(reservation["copy"]["count"], "[length(parameters('reservedSubnets'))]")
        self.assertNotIn("enableUsageReporting", json.dumps(reservation))

    def test_prod_firewall_route_is_opt_in_and_does_not_override_intravnet_prefixes(self):
        template = named_resource(self.hub, "existing-vnet-subnets")["properties"]["template"]
        route_table = next(r for r in resources(template) if r["type"] == "Microsoft.Network/routeTables")
        self.assertEqual(route_table["condition"], "[not(empty(parameters('apimFirewallIp')))]")
        routes = route_table["properties"]["routes"]
        default = next(r for r in routes if r["properties"]["addressPrefix"] == "0.0.0.0/0")
        self.assertEqual(default["properties"]["nextHopType"], "VirtualAppliance")
        self.assertEqual(
            default["properties"]["nextHopIpAddress"], "[parameters('apimFirewallIp')]",
        )
        self.assertEqual(
            {route["properties"]["addressPrefix"] for route in routes},
            {"0.0.0.0/0", "ApiManagement"},
        )
        subnet = named_resource(template, "apim-subnet")["properties"]["parameters"]["properties"]["value"]
        self.assertIn("routeTable", subnet)
        self.assertIn("parameters('apimFirewallIp')", subnet)
        self.assertIs(self.prod_parameters["managePrivateEndpointSubnet"], False)
        self.assertIs(ipaddress.ip_address(self.prod_parameters["apimFirewallIp"]).is_private, True)
        self.assertEqual(self.hub["parameters"]["apimFirewallIp"]["defaultValue"], "")

    def test_prod_dns_ids_and_reporting_are_forwarded_to_consumers(self):
        parameters = self.prod_parameters
        self.assertIs(parameters["enableUsageReporting"], True)
        self.assertIs(parameters["createAppInsightsDashboards"], True)
        self.assertRegex(parameters["storageAccountName"], r"^[a-z0-9]{3,24}$")
        zones = parameters["existingPrivateDnsZones"]
        for key in ("storageBlob", "storageFile", "storageTable", "storageQueue", "cosmosDb", "eventHub"):
            self.assertRegex(
                zones[key],
                r"^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Network/privateDnsZones/[^/]+$",
            )
        self.assertTrue(zones["storageFile"].endswith("/privatelink.file.core.windows.net"))
        self.assertNotEqual(zones["storageFile"].split("/")[2], zones["storageBlob"].split("/")[2])
        self.assertEqual(
            zones["apimGateway"],
            "/subscriptions/05a0e57b-2fd4-4141-bbac-b2192658c148/resourceGroups/"
            "rg-hub-dns-centralus/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net",
        )
        self.assertNotIn("/subscriptions/", parameters["dnsSubscriptionId"])
        storage = named_resource(self.hub, "storage")["properties"]["parameters"]
        self.assertEqual(
            storage["storageFileDnsZoneResourceId"]["value"], "[variables('existingStorageFileDnsZoneId')]",
        )
        cosmos = named_resource(self.hub, "cosmos-db")
        self.assertEqual(
            cosmos["properties"]["parameters"]["cosmosIdentityName"]["value"],
            "[parameters('cosmosIdentityName')]",
        )
        account = next(
            r for r in resources(cosmos["properties"]["template"])
            if r["type"] == "Microsoft.DocumentDB/databaseAccounts"
        )
        self.assertIn("parameters('cosmosIdentityName')", account["identity"])
        self.assertIn("UserAssigned", account["identity"])

    def test_customer_foundry_and_preserved_lab_alternative_are_mutually_exclusive(self):
        customer = self.prod_parameters
        lab = self.lab_parameters
        self.assertIsNone(customer["existingAiFoundry"])
        self.assertEqual(customer["existingLlmBackendConfig"], [])
        self.assertEqual(len(customer["aiFoundryInstances"]), 1)
        self.assertEqual(
            customer["aiFoundryInstances"][0]["name"], customer["aiFoundryResourceName"],
        )
        self.assertEqual(
            customer["aiFoundryInstances"][0]["defaultProjectName"], "proj-clasificaciondemandas-prod",
        )
        self.assertEqual(
            {model["name"]: (model["version"], model["capacity"]) for model in customer["aiFoundryModelsConfig"]},
            {"gpt-6-luna": ("2026-09-22", 120), "text-embedding-3-large": ("1", 150)},
        )
        for model in customer["aiFoundryModelsConfig"]:
            self.assertLess(model["aiserviceIndex"], len(customer["aiFoundryInstances"]))
        self.assertIn(
            customer["primaryFoundryEmbeddingModelName"],
            {model["name"] for model in customer["aiFoundryModelsConfig"]},
        )
        self.assertIsNotNone(lab["existingAiFoundry"])
        self.assertEqual(lab["aiFoundryInstances"], [])
        self.assertEqual(lab["aiFoundryModelsConfig"], [])
        self.assertEqual(
            lab["existingAiFoundry"]["resourceGroupName"], "rg-msassenus-1063",
        )
        models = lab["existingLlmBackendConfig"][0]["supportedModels"]
        self.assertIn(lab["primaryFoundryEmbeddingModelName"], {model["name"] for model in models})
        self.assertEqual(
            lab["existingLlmBackendConfig"][0]["endpoint"],
            "https://msassenus-1063-resource.cognitiveservices.azure.com/",
        )
        self.assertEqual(
            {model["name"]: model["capacity"] for model in models},
            {"gpt-6-luna": 500, "text-embedding-3-small": 120},
        )

    def test_subnets_fit_without_overlap_and_apim_bootstraps_public(self):
        vnet = ipaddress.ip_network(self.parameters["vnetAddressPrefix"])
        subnets = [
            ipaddress.ip_network(self.parameters[name])
            for name in ("apimSubnetPrefix", "privateEndpointSubnetPrefix", "functionAppSubnetPrefix")
        ]
        for index, subnet in enumerate(subnets):
            self.assertTrue(subnet.subnet_of(vnet))
            self.assertLessEqual(subnet.prefixlen, 26)
            for other in subnets[index + 1:]:
                self.assertFalse(subnet.overlaps(other))
        self.assertIs(self.parameters["apimV2UsePrivateEndpoint"], True)
        self.assertIs(self.parameters["apimV2PublicNetworkAccess"], True)
        self.assertEqual(self.parameters["apimSku"], "StandardV2")

    def test_network_prerequisites_create_only_the_hub_vnet_and_preserve_subnets(self):
        groups = [
            r for r in resources(self.network)
            if r["type"] == "Microsoft.Resources/resourceGroups"
        ]
        self.assertEqual(len(groups), 1)
        hub = named_resource(self.network, "dev-hub-network")
        self.assertEqual(
            hub["dependsOn"],
            ["[subscriptionResourceId('Microsoft.Resources/resourceGroups', "
             "parameters('resourceGroupName'))]"],
        )
        template = hub["properties"]["template"]
        vnet = next(
            r for r in resources(template) if r["type"] == "Microsoft.Network/virtualNetworks"
        )
        self.assertNotIn("subnets", vnet["properties"])
        self.assertEqual(set(vnet["properties"]), {"addressSpace"})
        self.assertEqual(
            {r["type"] for r in resources(template)},
            {
                "Microsoft.Network/virtualNetworks",
                "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
            },
        )

    def test_network_prerequisites_peer_both_directions_without_gateway_transit(self):
        hub = named_resource(self.network, "dev-hub-network")
        gateway = named_resource(self.network, "dev-gateway-network")
        self.assertEqual(
            gateway["dependsOn"],
            ["[extensionResourceId(format('/subscriptions/{0}/resourceGroups/{1}', "
             "subscription().subscriptionId, parameters('resourceGroupName')), "
             "'Microsoft.Resources/deployments', 'dev-hub-network')]"],
        )
        self.assertEqual(gateway["resourceGroup"], "[parameters('gatewayResourceGroupName')]")
        templates = [
            module["properties"]["template"] for module in (hub, gateway)
        ]
        for template, remote_id in zip(templates, ("gatewayVnetId", "hubVnetId")):
            peerings = [
                r for r in resources(template)
                if r["type"] == "Microsoft.Network/virtualNetworks/virtualNetworkPeerings"
            ]
            self.assertEqual(len(peerings), 1)
            properties = peerings[0]["properties"]
            self.assertEqual(
                properties["remoteVirtualNetwork"]["id"], f"[parameters('{remote_id}')]",
            )
            self.assertIs(properties["allowVirtualNetworkAccess"], True)
            for name in ("allowForwardedTraffic", "allowGatewayTransit", "useRemoteGateways"):
                self.assertIs(properties[name], False)
        self.assertEqual(
            hub["properties"]["parameters"]["gatewayVnetId"]["value"],
            "[resourceId(subscription().subscriptionId, parameters('gatewayResourceGroupName'), "
            "'Microsoft.Network/virtualNetworks', parameters('gatewayVnetName'))]",
        )
        self.assertIn(
            "dev-hub-network",
            gateway["properties"]["parameters"]["hubVnetId"]["value"],
        )

    def test_network_prerequisites_reuse_existing_dns_and_do_not_manage_application_gateway(self):
        gateway = named_resource(self.network, "dev-gateway-network")["properties"]["template"]
        self.assertEqual(
            {r["type"] for r in resources(gateway)},
            {
                "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
                "Microsoft.Network/privateDnsZones",
                "Microsoft.Network/privateDnsZones/virtualNetworkLinks",
            },
        )
        zones = [
            r for r in resources(gateway) if r["type"] == "Microsoft.Network/privateDnsZones"
        ]
        self.assertEqual([r["name"] for r in zones], ["privatelink.azure-api.net"])
        links = [
            r for r in resources(gateway)
            if r["type"] == "Microsoft.Network/privateDnsZones/virtualNetworkLinks"
        ]
        self.assertEqual(len(links), 3)
        for link in links:
            self.assertIs(link["properties"]["registrationEnabled"], False)
        apim_link = next(link for link in links if "copy" in link)
        self.assertEqual(
            apim_link["copy"]["count"],
            "[length(createArray("
            "createObject('name', parameters('hubVnetName'), 'id', parameters('hubVnetId')), "
            "createObject('name', parameters('gatewayVnetName'), 'id', "
            "resourceId('Microsoft.Network/virtualNetworks', parameters('gatewayVnetName')))))]",
        )
        vault_link = next(link for link in links if "vaultcore" in link["name"])
        self.assertIn("parameters('hubVnetName')", vault_link["name"])
        internal_link = next(link for link in links if "internalDnsZoneName" in link["name"])
        self.assertIn("parameters('hubVnetName')", internal_link["name"])


if __name__ == "__main__":
    unittest.main()
