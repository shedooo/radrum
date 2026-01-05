
import { describe, expect, it } from "vitest";
import { Cl, cvToValue } from "@stacks/transactions";

const CONTRACT = "radrum";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer") ?? accounts.get("wallet_1")!;
const user1 = accounts.get("wallet_1") ?? deployer;
const user2 = accounts.get("wallet_2") ?? user1;

type VaultInfo = {
  "liquid-assets": bigint;
  "deployed-assets": bigint;
  "total-assets": bigint;
  "total-shares": bigint;
  "share-price": bigint;
  paused: boolean;
  emergency: boolean;
  initialized: boolean;
  "auto-rebalance": boolean;
  "last-rebalance": bigint;
};

type VaultHealth = {
  "invariants-ok": boolean;
  "liquid-assets": bigint;
  "deployed-assets": bigint;
  "total-assets": bigint;
  "total-shares": bigint;
  "share-price": bigint;
  "needs-rebalancing": boolean;
  "allocation-drift": bigint;
};

type UserShares = {
  balance: bigint;
  "last-deposit": bigint;
  "total-deposited": bigint;
  "deposit-count": bigint;
};

type StrategyInfo = {
  name: string;
  balance: bigint;
  yield: bigint;
  active: boolean;
  "risk-level": bigint;
  apy: bigint;
  volatility: bigint;
  "max-drawdown": bigint;
  "sharpe-ratio": bigint;
};

const toBigInt = (value: number | bigint): bigint =>
  typeof value === "bigint" ? value : BigInt(value);

const parseTuple = <T>(tuple: Record<string, unknown>) => {
  const parsed: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(tuple)) {
    parsed[key] = cvToValue(value as any);
  }
  return parsed as T;
};

const unwrapOkUint = (result: any): bigint => {
  return toBigInt((result.value as any).value);
};

const readVaultInfo = (sender = deployer) => {
  const { result } = simnet.callReadOnlyFn(CONTRACT, "get-vault-info", [], sender);
  return parseTuple<VaultInfo>((result as any).value);
};

const readVaultHealth = (sender = deployer) => {
  const { result } = simnet.callReadOnlyFn(CONTRACT, "get-vault-health", [], sender);
  return parseTuple<VaultHealth>((result as any).value);
};

const readUserShares = (user: string, sender = deployer) => {
  const { result } = simnet.callReadOnlyFn(
    CONTRACT,
    "get-user-shares",
    [Cl.principal(user)],
    sender,
  );
  return parseTuple<UserShares>((result as any).value);
};

const readStrategy = (id: number, sender = deployer) => {
  const { result } = simnet.callReadOnlyFn(
    CONTRACT,
    "get-strategy-info",
    [Cl.uint(id)],
    sender,
  );
  expect(result).toBeSome(expect.anything());
  return parseTuple<StrategyInfo>((result as any).value.value);
};

const ensureInitialized = () => {
  const info = readVaultInfo();
  if (!info.initialized) {
    const { result } = simnet.callPublicFn(CONTRACT, "initialize", [], deployer);
    expect(result).toBeOk(Cl.bool(true));
  }
};

const mineBlocks = (count: number) => {
  for (let i = 0; i < count; i += 1) {
    simnet.mineBlock([]);
  }
};

describe("radrum core flows", () => {
  it("initializes once and exposes default state", () => {
    const before = readVaultInfo();

    const firstInit = simnet.callPublicFn(CONTRACT, "initialize", [], deployer);
    if (before.initialized) {
      expect(firstInit.result).toBeErr(Cl.uint(103));
    } else {
      expect(firstInit.result).toBeOk(Cl.bool(true));
    }

    const secondInit = simnet.callPublicFn(CONTRACT, "initialize", [], deployer);
    expect(secondInit.result).toBeErr(Cl.uint(103));

    const after = readVaultInfo();
    expect(after.initialized).toBe(true);

    const health = readVaultHealth();
    expect(health["invariants-ok"]).toBe(true);
  });

  it("mints shares on deposit and updates totals", () => {
    ensureInitialized();

    const beforeInfo = readVaultInfo();
    const beforeBalance = toBigInt(readUserShares(user1).balance);

    const depositAmount = 10000;
    const { result } = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(depositAmount), Cl.uint(1), Cl.none()],
      user1,
    );

    expect(result).toBeOk(expect.anything());
    const mintedShares = unwrapOkUint(result);

    const afterInfo = readVaultInfo();
    const afterBalance = toBigInt(readUserShares(user1).balance);

    const beforeTotalShares = toBigInt(beforeInfo["total-shares"]);
    const afterTotalShares = toBigInt(afterInfo["total-shares"]);

    expect(afterBalance - beforeBalance).toBe(mintedShares);
    expect(afterTotalShares - beforeTotalShares).toBe(mintedShares);

    const health = readVaultHealth();
    expect(health["invariants-ok"]).toBe(true);
  });

  it("enforces withdrawal cooldown and burns shares on execution", () => {
    ensureInitialized();

    const depositAmount = 20000;
    const deposit = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(depositAmount), Cl.uint(1), Cl.none()],
      user2,
    );
    expect(deposit.result).toBeOk(expect.anything());

    const mintedShares = unwrapOkUint(deposit.result);
    const requestedShares = mintedShares / 2n === 0n ? mintedShares : mintedShares / 2n;

    const request = simnet.callPublicFn(
      CONTRACT,
      "request-withdrawal",
      [Cl.uint(requestedShares)],
      user2,
    );
    expect(request.result).toBeOk(Cl.bool(true));

    const earlyExit = simnet.callPublicFn(CONTRACT, "execute-withdrawal", [], user2);
    expect(earlyExit.result).toBeErr(Cl.uint(108));

    mineBlocks(145);

    const beforeExecuteBalance = toBigInt(readUserShares(user2).balance);
    const execute = simnet.callPublicFn(CONTRACT, "execute-withdrawal", [], user2);
    expect(execute.result).toBeOk(expect.anything());

    const afterExecuteBalance = toBigInt(readUserShares(user2).balance);
    expect(beforeExecuteBalance - afterExecuteBalance).toBe(requestedShares);

    const health = readVaultHealth();
    expect(health["invariants-ok"]).toBe(true);
  });

  it("harvest resets simulated yield and keeps invariants", () => {
    ensureInitialized();

    const yieldAmount = 5000;
    const beforeYield = toBigInt(readStrategy(1).yield);

    const simulate = simnet.callPublicFn(
      CONTRACT,
      "simulate-yield",
      [Cl.uint(1), Cl.uint(yieldAmount)],
      deployer,
    );
    expect(simulate.result).toBeOk(Cl.uint(yieldAmount));

    const afterSimYield = toBigInt(readStrategy(1).yield);
    expect(afterSimYield - beforeYield).toBe(BigInt(yieldAmount));

    const harvest = simnet.callPublicFn(CONTRACT, "harvest-all-strategies", [], deployer);
    expect(harvest.result).toBeOk(expect.anything());

    const afterHarvestYield = toBigInt(readStrategy(1).yield);
    expect(afterHarvestYield).toBe(0n);

    const health = readVaultHealth();
    expect(health["invariants-ok"]).toBe(true);
  });
});
