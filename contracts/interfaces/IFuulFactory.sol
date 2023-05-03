// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IFuulFactory {
    struct FeesInformation {
        uint256 protocolFee;
        uint256 attributorFee;
        uint256 clientFee;
        address protocolFeeCollector;
        uint256 nftFixedFeeAmount;
        address nftFeeCurrency;
    }
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed deployedAddress,
        address indexed eventSigner,
        string projectInfoURI,
        address clientFeeCollector
    );

    function createFuulProject(
        address _projectAdmin,
        address _projectEventSigner,
        string memory _projectInfoURI,
        address _clientFeeCollector
    ) external;

    error ZeroAddress();

    function projects(uint256 projectId) external returns (address);

    function totalProjectsCreated() external view returns (uint256);

    function getUserProjectByIndex(
        address account,
        uint256 index
    ) external view returns (address);

    function getUserProjectCount(
        address account
    ) external view returns (uint256);

    function fuulManager() external view returns (address);

    function setFuulManager(address _fuulManager) external;

    /*╔═════════════════════════════╗
      ║        FEES VARIABLES       ║
      ╚═════════════════════════════╝*/

    function protocolFee() external view returns (uint256 fees);

    function protocolFeeCollector() external view returns (address);

    function getFeesInformation()
        external
        returns (FeesInformation memory, address);

    function clientFee() external view returns (uint256 fees);

    function attributorFee() external view returns (uint256 fees);

    function nftFeeCurrency() external view returns (address);

    function setProtocolFee(uint256 value) external;

    function setClientFee(uint256 value) external;

    function setAttributorFee(uint256 value) external;

    function setNftFixedFeeAmounte(uint256 _value) external;

    function setNftFeeCurrency(address newCurrency) external;
}
