// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol"; //"@superfluid-finance/ethereum-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

contract RedirectAll is SuperAppBase {
    ISuperfluid private _host; // host
    IConstantFlowAgreementV1 private _cfa; // the stored constant flow agreement class address
    ISuperToken private _acceptedToken; // accepted token
    address private _receiver;

    struct ReceiverData {
      address to;
      uint256 proportion;
    }

    // Sender => to / proportion
    mapping (address => ReceiverData[]) internal _userFlows;

    constructor(
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken,
        address receiver
    ) {
        require(address(host) != address(0), "host is zero address");
        require(address(cfa) != address(0), "cfa is zero address");
        require(
            address(acceptedToken) != address(0),
            "acceptedToken is zero address"
        );
        require(address(receiver) != address(0), "receiver is zero address");
        require(!host.isApp(ISuperApp(receiver)), "receiver is an app");

        _host = host;
        _cfa = cfa;
        _acceptedToken = acceptedToken;
        _receiver = receiver;
        // sets creator Id and proportion to address that called this contract
        ReceiverData[0].to = receiver;
        ReceiverData[0].proportion = 50;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);
    }

    /**************************************************************************
     * Redirect Logic
     *************************************************************************/

    // is this function still needed?
    /*function currentReceiver()
        external
        view
        returns (
            uint256 startTime,
            address receiver,
            int96 flowRate
        )
    {
        if (_receiver != address(0)) {
            (startTime, flowRate, , ) = _cfa.getFlow(
                _acceptedToken,
                address(this),
                _receiver
            );
            receiver = _receiver;
        }
    } */

    function createMultiFlows(
      ISuperToken acceptedToken,
      address[] calldata receivers,
      uint256[] calldata proportions,
      bytes calldata ctx
    )
      external
      onlyHost
      returns(bytes memory newCtx) {
      require(receivers.length == proportions.length, "number of receivers does not equal flowrates");
      (,,address sender,,) = _host.decodeCtx(ctx);
      require(_userFlows[sender].length == 0, "Multiflow already created.");

      newCtx = _host.chargeGasFee(ctx, 30000);

      (, int256 receivingFlowRate,,) = _cfa.getFlow(
        acceptedToken,
        sender,
        address(this)
      );
      // require(receivingFlowRate == 0, "Updates are not supported, go to YAM");
      // i=0 is set for creator of NFT. 1+ is for contributors
      for(uint256 i = 1; i < receivers.length; i++) {
        _userFlows[sender].push(ReceiverData(receivers[i], proportions[i] * 50 ));
      }

      return newCtx;
    }


    event ReceiverChanged(address receiver);

    function _updateMultiFlow(
        ISuperToken superToken,
        address sender,
        bytes4 selector,
        int96 receivingFlowRate,
        bytes calldata ctx
    )
        private
        returns (bytes memory newCtx)
    {
        uint256 sum = _sumProportions(_userFlows[sender]);
        require(sum != 0 , "MFA: Sum is zero");

        newCtx = ctx;
        for(uint256 i = 0; i < _userFlows[sender].length; i++) {
            require(_userFlows[sender][i].proportion > 0, "Proportion > 0");
            int96 targetFlowrate = (int96(_userFlows[sender][i].proportion) * receivingFlowRate) / int96(sum);
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    selector,
                    superToken,
                    _userFlows[sender][i].to,
                    targetFlowrate,
                    new bytes(0)
                ),
                "0x",
                newCtx
            );
        }
        return newCtx;
    }

    // @dev Change the Receiver of the total flow
    function _changeReceiver(address newReceiver) internal {
        _receiver = ReceiverData[0].to;
        require(newReceiver != address(0), "New receiver is zero address");
        // @dev because our app is registered as final, we can't take downstream apps
        require(
            !_host.isApp(ISuperApp(newReceiver)),
            "New receiver can not be a superApp"
        );
        if (newReceiver == _receiver) return;
        // @dev delete flow to old receiver
        (, int96 outFlowRate, , ) = _cfa.getFlow(
            _acceptedToken,
            address(this),
            _receiver
        ); //CHECK: unclear what happens if flow doesn't exist.
        if (outFlowRate > 0) {
            _host.callAgreement(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.deleteFlow.selector,
                    _acceptedToken,
                    address(this),
                    _receiver,
                    new bytes(0)
                ),
                "0x"
            );
            // @dev create flow to new receiver
            _host.callAgreement(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.createFlow.selector,
                    _acceptedToken,
                    newReceiver,
                    _cfa.getNetFlow(_acceptedToken, address(this)),
                    new bytes(0)
                ),
                "0x"
            );
        }
        // @dev set global receiver to new receiver
        _receiver = newReceiver;
        ReceiverData[0].to = newReceiver;
        emit ReceiverChanged(_receiver);
    }

    /**************************************************************************
     * SuperApp callbacks
     *************************************************************************/

    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx) {

        (,,address sender,,) = _host.decodeCtx(_ctx);
        require(_userFlows[sender].length > 0 , "MFA: Create Multi Flow first");
        (, int96 receivingFlowRate,,) = _cfa.getFlowByID(_superToken, _agreementId);

        require(receivingFlowRate != 0, "MFA: not zero pls");

        newCtx = _updateMultiFlow(_superToken, sender, _cfa.createFlow.selector, receivingFlowRate, _ctx);
        return newCtx;
    }

    function beforeAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata /*ctx*/
    )
        external
        view
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory cbdata) {

        require(_agreementClass == address(_cfa), "MFA: Unsupported agreement");
        (, int256 oldFlowRate,,) = _cfa.getFlowByID(_superToken, _agreementId);
        return abi.encode(oldFlowRate);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata _agreementData,
        bytes calldata _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx) {

        (,,address sender,,) = _host.decodeCtx(_ctx);
        (, int96 newFlowRate,,) = _cfa.getFlowByID(_superToken, _agreementId);

        int96 oldFlowRate = abi.decode(_cbdata, (int96));
        require(newFlowRate > oldFlowRate, "MFA: only increasing flow rate"); // Funky logic for testing purpose

        newCtx = _updateMultiFlow(_superToken, sender, _cfa.updateFlow.selector, newFlowRate, _ctx);
        return newCtx;
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, //_agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyHost
        returns (bytes memory newCtx) {

        // According to the app basic law, we should never revert in a termination callback
        if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass))
            return _ctx;

        (,,address sender,,) = _host.decodeCtx(_ctx);
        newCtx = _ctx;
        for(uint256 i = 0; i < _userFlows[sender].length; i++) {
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.deleteFlow.selector,
                    _superToken,
                    address(this),
                    _userFlows[sender][i].to,
                    new bytes(0)
                ),
                newCtx
                );
            }
            delete _userFlows[sender];
            return newCtx;
    }

    function _isSameToken(ISuperToken superToken) private view returns (bool) {
        return address(superToken) == address(_acceptedToken);
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return
            ISuperAgreement(agreementClass).agreementType() ==
            keccak256(
                "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
            );
    }

    function _sumProportions(ReceiverData[] memory receivers) internal pure returns(uint256 sum) {
      for(uint256 i = 0; i < receivers.length; i++) {
        sum += receivers[i].proportion;
      }
    }

    modifier onlyHost() {
        require(
            msg.sender == address(_host),
            "RedirectAll: support only one host"
        );
        _;
    }

    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        require(_isSameToken(superToken), "RedirectAll: not accepted token");
        require(_isCFAv1(agreementClass), "RedirectAll: only CFAv1 supported");
        _;
    }
}
