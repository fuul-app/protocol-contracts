// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "./interfaces/IFuulManager.sol";

contract FuulManager is
    IFuulManager,
    AccessControlEnumerable,
    ReentrancyGuard,
    Pausable
{
    using ERC165Checker for address;

    // Attributor role
    bytes32 public constant ATTRIBUTOR_ROLE = keccak256("ATTRIBUTOR_ROLE");
    // Pauser role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Interfaces for ERC721 and ERC1155 contracts
    bytes4 public constant IID_IERC1155 = type(IERC1155).interfaceId;
    bytes4 public constant IID_IERC721 = type(IERC721).interfaceId;

    // Amount of time that must elapse between a project's application to remove funds from its budget and the actual removal of those funds.
    uint256 public projectBudgetCooldown = 30 days;

    // Period of time that a project can remove funds after cooldown. If they don't remove in this period, they will have to apply to remove again.
    uint256 public projectRemoveBudgetPeriod = 30 days;

    // Amount of time that must elapse after {claimCooldownPeriodStarted} for the cumulative amount to be restarted
    uint256 public claimCooldown = 1 days;

    // Fixed fee for NFT rewards
    uint256 public nftFixedFeeAmount = 0.1 ether;

    // Protocol fee percentage. 1 => 0.01%
    uint256 public protocolFee = 100;

    // Client fee. 1 => 0.01%
    uint256 public clientFee = 100;

    // Attributor fee. 1 => 0.01%
    uint256 public attributorFee = 100;

    // Address that will collect protocol fees
    address public protocolFeeCollector;

    // Currency paid for NFT fixed fees
    address public nftFeeCurrency;

    // Mapping users and currency with total amount claimed
    mapping(address => mapping(address => uint256)) public usersClaims;

    // Mapping addresses with tokens info
    mapping(address => CurrencyToken) public currencyTokens;

    /*╔═════════════════════════════╗
      ║         CONSTRUCTOR         ║
      ╚═════════════════════════════╝*/

    /**
     * @dev Grants roles to `_attributor`, `_pauser` and DEFAULT_ADMIN_ROLE to the deployer.
     *
     * Adds the initial `acceptedERC20CurrencyToken` as an accepted currency with its `initialTokenLimit`.
     * Adds the zero address (native token) as an accepted currency with its `initialNativeTokenLimit`.
     */
    constructor(
        address _attributor,
        address _pauser,
        address acceptedERC20CurrencyToken,
        uint256 initialTokenLimit,
        uint256 initialNativeTokenLimit,
        address _protocolFeeCollector,
        address _nftFeeCurrency
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(ATTRIBUTOR_ROLE, _attributor);
        _setupRole(PAUSER_ROLE, _pauser);

        _addCurrencyToken(acceptedERC20CurrencyToken, initialTokenLimit);
        _addCurrencyToken(address(0), initialNativeTokenLimit);

        protocolFeeCollector = _protocolFeeCollector;
        nftFeeCurrency = _nftFeeCurrency;
    }

    /*╔═════════════════════════════╗
      ║       REMOVE VARIABLES      ║
      ╚═════════════════════════════╝*/

    /**
     * @dev Sets the period for `claimCooldown`.
     *
     * Requirements:
     *
     * - `_period` must be different from the current one.
     * - Only admins can call this function.
     */
    function setClaimCooldown(
        uint256 _period
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_period == claimCooldown) {
            revert InvalidArgument();
        }

        claimCooldown = _period;
    }

    /**
     * @dev Sets the period for `projectBudgetCooldown`.
     *
     * Requirements:
     *
     * - `_period` must be different from the current one.
     * - Only admins can call this function.
     */
    function setProjectBudgetCooldown(
        uint256 _period
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_period == projectBudgetCooldown) {
            revert InvalidArgument();
        }

        projectBudgetCooldown = _period;
    }

    /**
     * @dev Sets the period for `projectRemoveBudgetPeriod`.
     *
     * Requirements:
     *
     * - `_period` must be different from the current one.
     * - Only admins can call this function.
     */
    function setProjectRemoveBudgetPeriod(
        uint256 _period
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_period == projectRemoveBudgetPeriod) {
            revert InvalidArgument();
        }

        projectRemoveBudgetPeriod = _period;
    }

    /**
     * @dev Returns removal info. The function purpose is to call only once from {FuulProject} when needing this info.
     */
    function getBudgetRemoveInfo()
        external
        view
        returns (uint256 cooldown, uint256 removeWindow)
    {
        return (projectBudgetCooldown, projectRemoveBudgetPeriod);
    }

    /*╔═════════════════════════════╗
      ║        FEES VARIABLES       ║
      ╚═════════════════════════════╝*/

    /**
     * @dev Returns all fees for attribution. The function purpose is to call only once from {FuulProject} when needing this info.
     *
     */
    function getFeesInformation()
        external
        view
        returns (FeesInformation memory)
    {
        return
            FeesInformation({
                protocolFee: protocolFee,
                attributorFee: attributorFee,
                clientFee: clientFee,
                protocolFeeCollector: protocolFeeCollector,
                nftFixedFeeAmount: nftFixedFeeAmount,
                nftFeeCurrency: nftFeeCurrency
            });
    }

    /**
     * @dev Sets the protocol fees for each attribution.
     *
     * Requirements:
     *
     * - `_value` must be different from the current one.
     * - Only admins can call this function.
     */
    function setProtocolFee(
        uint256 _value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_value == protocolFee) {
            revert InvalidArgument();
        }

        protocolFee = _value;
    }

    /**
     * @dev Sets the fees for the client that was used to create the project.
     *
     * Requirements:
     *
     * - `_value` must be different from the current one.
     * - Only admins can call this function.
     */
    function setClientFee(
        uint256 _value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_value == clientFee) {
            revert InvalidArgument();
        }

        clientFee = _value;
    }

    /**
     * @dev Sets the fees for the attributor.
     *
     * Requirements:
     *
     * - `_value` must be different from the current one.
     * - Only admins can call this function.
     */
    function setAttributorFee(
        uint256 _value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_value == attributorFee) {
            revert InvalidArgument();
        }

        attributorFee = _value;
    }

    /**
     * @dev Sets the fixed fee amount for NFT rewards.
     *
     * Requirements:
     *
     * - `_value` must be different from the current one.
     * - Only admins can call this function.
     */
    function setNftFixedFeeAmounte(
        uint256 _value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_value == nftFixedFeeAmount) {
            revert InvalidArgument();
        }

        nftFixedFeeAmount = _value;
    }

    /**
     * @dev Sets the currency that will be used to pay NFT rewards fees.
     *
     * Requirements:
     *
     * - `_value` must be different from the current one.
     * - Only admins can call this function.
     */
    function setNftFeeCurrency(
        address newCurrency
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newCurrency == nftFeeCurrency) {
            revert InvalidArgument();
        }

        nftFeeCurrency = newCurrency;
    }

    /**
     * @dev Sets the protocol fee collector address.
     *
     * Requirements:
     *
     * - `_value` must be different from the current one.
     * - Only admins can call this function.
     */
    function setProtocolFeeCollector(
        address newCollector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newCollector == protocolFeeCollector) {
            revert InvalidArgument();
        }

        protocolFeeCollector = newCollector;
    }

    /*╔═════════════════════════════╗
      ║       TOKEN CURRENCIES      ║
      ╚═════════════════════════════╝*/

    /**
     * @dev Returns TokenType enum from a tokenAddress.
     */
    function getTokenType(
        address tokenAddress
    ) external view returns (TokenType tokenType) {
        return currencyTokens[tokenAddress].tokenType;
    }

    /**
     * @dev Returns whether the currency token is accepted.
     */
    function isCurrencyTokenAccepted(
        address tokenAddress
    ) public view returns (bool isAccepted) {
        return currencyTokens[tokenAddress].isActive;
    }

    /**
     * @dev Adds a currency token.
     * See {_addCurrencyToken}
     *
     * Requirements:
     *
     * - Only admins can call this function.
     */
    function addCurrencyToken(
        address tokenAddress,
        uint256 claimLimitPerCooldown
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addCurrencyToken(tokenAddress, claimLimitPerCooldown);
    }

    /**
     * @dev Removes a currency token.
     *
     * Notes:
     * - Projects will not be able to deposit with the currency token.
     * - We don't remove the `currencyToken` object because users will still be able to claim/remove it
     *
     * Requirements:
     *
     * - `tokenAddress` must be accepted.
     * - Only admins can call this function.
     */
    function removeCurrencyToken(
        address tokenAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isCurrencyTokenAccepted(tokenAddress)) {
            revert TokenCurrencyNotAccepted();
        }
        CurrencyToken storage currency = currencyTokens[tokenAddress];

        currency.isActive = false;
    }

    /**
     * @dev Sets a new `claimLimitPerCooldown` for a currency token.
     *
     * Notes:
     * We are not checking that the tokenAddress is accepted because
     * users can claim from unaccepted currencies.
     *
     * Requirements:
     *
     * - `limit` must be greater than zero.
     * - `limit` must be different from the current one.
     * - Only admins can call this function.
     */
    function setCurrencyTokenLimit(
        address tokenAddress,
        uint256 limit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        CurrencyToken storage currency = currencyTokens[tokenAddress];

        if (limit == 0 || limit == currency.claimLimitPerCooldown) {
            revert InvalidArgument();
        }

        currency.claimLimitPerCooldown = limit;
    }

    /*╔═════════════════════════════╗
      ║            PAUSE            ║
      ╚═════════════════════════════╝*/

    /**
     * @dev Pauses the contract and all {FuulProject}s.
     * See {Pausable.sol}
     *
     * Requirements:
     *
     * - Only addresses with the PAUSER_ROLE can call this function.
     */
    function pauseAll() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract and all {FuulProject}s.
     * See {Pausable.sol}
     *
     * Requirements:
     *
     * - Only addresses with the PAUSER_ROLE can call this function.
     */
    function unpauseAll() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Returns whether the contract is paused.
     * See {Pausable.sol}
     */
    function isPaused() external view returns (bool) {
        return paused();
    }

    /*╔═════════════════════════════╗
      ║      ATTRIBUTE & CLAIM      ║
      ╚═════════════════════════════╝*/

    /**
     * @dev Attributes: calls the `attributeTransactions` function in {FuulProject} from an array of {AttributionEntity}.
     *
     * Requirements:
     *
     * - Contract should not be paused.
     * - Only addresses with the ATTRIBUTOR_ROLE can call this function.
     */

    function attributeTransactions(
        AttributionEntity[] memory attributions,
        address attributorFeeCollector
    ) external whenNotPaused nonReentrant onlyRole(ATTRIBUTOR_ROLE) {
        unchecked {
            uint256 attributionLength = attributions.length;
            for (uint256 i = 0; i < attributionLength; i++) {
                IFuulProject.Attribution[]
                    memory projectAttributions = attributions[i]
                        .projectAttributions;

                IFuulProject(attributions[i].projectAddress)
                    .attributeTransactions(
                        projectAttributions,
                        attributorFeeCollector
                    );
            }
        }
    }

    /**
     * @dev Claims: calls the `claimFromProject` function in {FuulProject} from an array of of {ClaimCheck}.
     *
     * Requirements:
     *
     * - Contract should not be paused.
     */
    function claim(
        ClaimCheck[] calldata claimChecks
    ) external whenNotPaused nonReentrant {
        uint256 checksLength = claimChecks.length;

        for (uint256 i = 0; i < checksLength; i++) {
            ClaimCheck memory claimCheck = claimChecks[i];

            // Send
            uint256 tokenAmount;
            address currency;
            (tokenAmount, currency) = IFuulProject(claimCheck.projectAddress)
                .claimFromProject(
                    claimCheck.currency,
                    _msgSender(),
                    claimCheck.tokenIds,
                    claimCheck.amounts
                );

            CurrencyToken storage currencyInfo = currencyTokens[currency];

            // Limit

            if (tokenAmount > currencyInfo.claimLimitPerCooldown) {
                revert OverTheLimit();
            }

            if (
                currencyInfo.claimCooldownPeriodStarted + claimCooldown >
                block.timestamp
            ) {
                // If cooldown not ended -> check that the limit is not reached and then sum amount to cumulative

                if (
                    currencyInfo.cumulativeClaimPerCooldown + tokenAmount >
                    currencyInfo.claimLimitPerCooldown
                ) {
                    revert OverTheLimit();
                }

                currencyInfo.cumulativeClaimPerCooldown += tokenAmount;
            } else {
                // If cooldown ended -> set new values for cumulative and time (amount limit is checked before)
                currencyInfo.cumulativeClaimPerCooldown = tokenAmount;
                currencyInfo.claimCooldownPeriodStarted = block.timestamp;
            }

            // Update values
            usersClaims[_msgSender()][currency] += tokenAmount;
        }
    }

    /*╔═════════════════════════════╗
      ║      INTERNAL ADD TOKEN     ║
      ╚═════════════════════════════╝*/

    /**
     * @dev Returns whether the address is an ERC20 token.
     */
    function isERC20(address tokenAddress) internal view returns (bool) {
        IERC20 token = IERC20(tokenAddress);
        try token.totalSupply() {
            try token.allowance(_msgSender(), address(this)) {
                return true;
            } catch {}
        } catch {}
        return false;
    }

    /**
     * @dev Returns whether the address is a contract.
     */
    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /**
     * @dev Adds a new `tokenAddress` to accepted currencies with its
     * corresponding `claimLimitPerCooldown`.
     *
     * Requirements:
     *
     * - `tokenAddress` must be a contract (excepting for the zero address).
     * - `tokenAddress` must not be accepted yet.
     * - `claimLimitPerCooldown` should be greater than zero.
     */
    function _addCurrencyToken(
        address tokenAddress,
        uint256 claimLimitPerCooldown
    ) internal {
        if (tokenAddress != address(0) && !isContract(tokenAddress)) {
            revert InvalidArgument();
        }

        if (isCurrencyTokenAccepted(tokenAddress)) {
            revert TokenCurrencyAlreadyAccepted();
        }

        if (claimLimitPerCooldown == 0) {
            revert InvalidArgument();
        }

        TokenType tokenType;

        if (tokenAddress == address(0)) {
            tokenType = TokenType(0);
        } else if (isERC20(tokenAddress)) {
            tokenType = TokenType(1);
        } else if (tokenAddress.supportsInterface(IID_IERC721)) {
            tokenType = TokenType(2);
        } else if (tokenAddress.supportsInterface(IID_IERC1155)) {
            tokenType = TokenType(3);
        } else {
            revert InvalidArgument();
        }

        currencyTokens[tokenAddress] = CurrencyToken({
            tokenType: tokenType,
            claimLimitPerCooldown: claimLimitPerCooldown,
            cumulativeClaimPerCooldown: 0,
            claimCooldownPeriodStarted: block.timestamp,
            isActive: true
        });
    }
}
