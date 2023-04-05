// SPDX-License-Identifier: MIT
import "./IFuulManager.sol";

pragma solidity ^0.8.18;

interface IFuulProject {
    /*╔═════════════════════════════╗
      ║           EVENTS            ║
      ╚═════════════════════════════╝*/

    // uint256[] tokenIds: used in ERC721 and ERC1155
    // uint256[] amounts: used in ERC1155

    event CampaignMetadataUpdated(uint256 campaignId, string campaignURI);

    event CampaignCreated(
        address indexed account,
        address currency,
        uint256 campaignTokenId,
        IFuulManager.TokenType tokenType,
        string _campaignURI
    );

    event BudgetDeposited(
        address indexed account,
        uint256 amount,
        address currency,
        uint256 campaignTokenId,
        IFuulManager.TokenType tokenType,
        uint256[] tokenIds,
        uint256[] amounts
    );

    event BudgetRemoved(
        address indexed account,
        uint256 amount,
        address currency,
        uint256 campaignTokenId,
        IFuulManager.TokenType tokenType,
        uint256[] tokenIds,
        uint256[] amounts
    );

    event Claimed(
        string voucherId,
        uint256 campaignTokenId,
        address indexed account,
        address currency,
        uint256 amount,
        uint256[] rewardTokenIds,
        uint256[] amounts
    );

    /*╔═════════════════════════════╗
      ║           ERRORS            ║
      ╚═════════════════════════════╝*/

    error Unauthorized(address sender, address requiredSender);
    error ManagerIsPaused();
    error CampaignNotExists(uint256 campaignId);
    error EmptyCampaignURI(string campaignURI);
    error TokenCurrencyNotAccepted(address tokenAddress);

    error CampaignNotInactive(uint256 campaignId);
    error CampaignNotActive(uint256 campaignId);
    // error InsufficientBalance(uint256 available, uint256 required);
    error IncorrectBalance(uint256 amount);
    error CooldownPeriodNotFinished(uint256 now, uint256 required);
    error ZeroAddress();

    // error SameValue(address value);

    /*╔═════════════════════════════╗
      ║       PUBLIC VARIABLES      ║
      ╚═════════════════════════════╝*/

    function fuulFactory() external view returns (address);

    function campaigns(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256,
            uint256,
            address,
            uint256,
            string memory,
            IFuulManager.TokenType
        );

    /*╔═════════════════════════════╗
      ║     FROM OTHER CONTRACTS    ║
      ╚═════════════════════════════╝*/

    function fuulManagerAddress() external view returns (address);

    function fuulManagerInstance() external view returns (IFuulManager);

    /*╔═════════════════════════════╗
      ║         CAMPAIGNS           ║
      ╚═════════════════════════════╝*/

    function campaignsCreated() external view returns (uint256);

    function createCampaign(string memory _tokenURI, address currency) external;

    function reactivateCampaign(uint256 tokenId) external;

    function deactivateCampaign(uint256 tokenId) external;

    function setCampaignURI(uint256 _tokenId, string memory _tokenURI) external;

    /*╔═════════════════════════════╗
      ║           DEPOSIT           ║
      ╚═════════════════════════════╝*/

    function depositFungibleToken(
        uint256 campaignTokenId,
        uint256 amount
    ) external payable;

    function depositNFTToken(
        uint256 campaignTokenId,
        uint256[] memory rewardTokenIds,
        uint256[] memory amounts
    ) external;

    /*╔═════════════════════════════╗
      ║           REMOVE            ║
      ╚═════════════════════════════╝*/

    function getBudgetCooldownPeriod(
        uint256 deactivatedAt
    ) external view returns (uint256);

    function removeFungibleBudget(
        uint256 campaignTokenId,
        uint256 amount
    ) external;

    function removeNFTBudget(
        uint256 campaignTokenId,
        uint256[] memory rewardTokenIds,
        uint256[] memory amounts
    ) external;

    /*╔═════════════════════════════╗
      ║            CLAIM            ║
      ╚═════════════════════════════╝*/

    function claimFromCampaign(
        IFuulManager.ClaimVoucher calldata voucher
    ) external returns (uint256);

    /*╔═════════════════════════════╗
      ║          EMERGENCY          ║
      ╚═════════════════════════════╝*/

    function emergencyWithdrawFungibleTokens(
        address to,
        address currency
    ) external;

    function emergencyWithdrawNFTTokens(
        address to,
        address currency,
        uint256[] memory rewardTokenIds,
        uint256[] memory amounts
    ) external;
}
