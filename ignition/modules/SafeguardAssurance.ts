import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SafeguardAssuranceModule", (m) => {
  const safetyLead = m.getAccount(0);
  const registry = m.contract("SafeguardAssurance", [safetyLead]);
  return { registry };
});
