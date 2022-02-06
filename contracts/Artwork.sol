// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RedirectAll, ISuperToken, IConstantFlowAgreementV1, ISuperfluid} from "./RedirectAll.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
//import "@openzeppelin/contracts/utils/Counters.sol";

contract Artwork is ERC721, RedirectAll {
  // using Counters for Counters.Counter;

  uint256 public tokenId;

  // data structure to store art data
  struct Art {
    uint256 id;
    string URI;
    uint256 donationAmount;
    address payable author;
  }

  // mapping to store URIs from IPFS
  mapping (uint256 => string) private _tokenURIs;
  // mapping to store art struct data
  mapping (uint256 => Art) public artwork;
  // mapping to track donators/contributors
  mapping (address => uint256) public contributors;


  // Event emitted when art is created
  event artCreated(
    uint256 id,
    string URI,
    uint256 donationAmount,
    address payable author
  );

  // Event emitted when there is a donation
  event donateToArt(
    uint256 id,
    string URI,
    uint256 donationAmount,
    address payable author
  );

  constructor(
    string memory name,
    string memory symbol,
    ISuperfluid host,
    IConstantFlowAgreementV1 cfa,
    ISuperToken acceptedToken
  )
    ERC721(name, symbol)
    RedirectAll(
      host,
      cfa,
      acceptedToken,
      msg.sender
    ) {
    tokenId = 0;
  }

  function mint(string memory _tokenURI) public {
    tokenId++;
    _safeMint(msg.sender, tokenId);
    _setTokenURI(tokenId, _tokenURI);

    artwork[tokenId].push(Art(
      tokenId,
      _tokenURI,
      0,
      payable(msg.sender)
    ));
    emit artCreated(tokenId, _tokenURI, 0, payable(msg.sender));


  }

  function _setTokenURI(uint256 _tokenId, string memory _tokenURI) internal virtual {
    // Checks if tokenId exists
    require( _exists(_tokenId), "ERC721Metadata: URI set of nonexistent token.");
    _tokenURIs[_tokenId].push(_tokenURI);
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns(string memory) {
    require( _exists(_tokenId), "ERC721Metadata: URI set of nonexistent token.");
    return _tokenURIs[_tokenId];
  }

  function donateToArtOwner(uint256 _id) public payable {
    require(_id > 0 && _id <= tokenId);
    bytes memory ctx;

    Art memory _art = artwork[_id];
    address payable _author = _art.author;
    payable(address(_author)).transfer(msg.value);
    // sum up donation amount to track percentage of royalties
    _art.donationAmount = _art.donationAmount + msg.value;
    artwork[_id] = _art;

    // store address of contributor for future royalties
    contributors[msg.sender].push(msg.value);

    emit donateToArt(_id, _art.URI, _art.donationAmount, _author);

    // something wrong here
    createMultiFlows(acceptedToken, msg.sender, (msg.value / _art.donationAmount), ctx ); // what to put for ctx?
  }

  function _beforeTokenTransfer(
    address /*from*/,
    address to,
    uint256 /*tokenId*/
  ) internal override {
    _changeReceiver(to);
  }
}
