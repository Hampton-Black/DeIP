// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./artStorage.sol";
import "./Artwork.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SuperTokenFactoryBase} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";

// Does this need to inherit Artwork?
contract Royalties is artStorage, Artwork, SuperTokenFactoryBase {
    using EnumerableSet for EnumerableSet.UintSet;

    // Events
    event ListNFT(uint256 tokenId);
    event UnlistNFT(uint256 listingId);
    event TerminateRental(uint256 listingId);
    event Returned(uint256 listingId);

    // Create Supertoken wrapper: Polygon network
    // create USDCx: "0xCAa7349CEA390F89641fe306D93591f87595dc1F"
    uint256 USDCx = createERC20Wrapper(address("0x2791bca1f2de4661ed88a30c99a7a9449aa84174"), uint8(1), "Super USDC", "USDCx");

    function getListingCount() public view returns (uint) {
        return _getListingCount();
    }

    // [Feature 1] Main listings dashboard
    // This function returns all listings stored in the contract.
    function viewAllListings() public view returns (Listing[] memory) {
        uint256[] memory listingIds = _getListingIds();
        Listing[] memory listings = new Listing[](listingIds.length);
        for (uint i = 0; i < listingIds.length; i++) {
            listings[i] = _getListingById(listingIds[i]);
        }
        return listings;
    }

    // [Feature 1] Main listings dashboard
    // Front end will invoke this function to deposit collateral and receive the NFT to the borrower's address
    function borrow(uint256 listingId) public payable {
        require(_listingExists(listingId), "listing does not exist");

        Listing storage listing = _getListingById(listingId);
        require(listing.rental.rentedAt == 0, "not an available listing");
        require(listing.lenderAddress != msg.sender, "cannot rent your own token");

        uint payment = _calculatePayment(listing);

        // change payment from msg.value to super tokens? included in web app js?
        require(msg.value == payment, "must send the exact payment");

        listing.rental.borrowerAddress = payable(msg.sender);
        listing.rental.rentedAt = block.timestamp;

        IERC721 token = IERC721(listing.tokenAddress);
        token.safeTransferFrom(listing.lenderAddress, msg.sender, listing.tokenId);
    }

    // [Feature 2] Lender's dashboard
    // Returns a list of all the listings owned by the sender
    function viewOwnedOngoingListingsAndRentals() public view returns (Listing[] memory){
        // Note: Dynamic arrays are not allowed unless they are storage
        // so we need to allocate a statically sized-array to return.
        // We can probably optimize this, but this should functionally work for now.
        uint listingsOwned = 0;
        for (uint i = 0; i < listingsSet.length(); i++) {
            Listing memory listing = _getListingById(listingsSet.at(i));
            if (listing.lenderAddress == msg.sender) {
                listingsOwned++;
            }
        }
        Listing[] memory ownerListings = new Listing[](listingsOwned);
        uint j = 0;
        for (uint i = 0; i < listingsSet.length(); i++) {
            Listing memory listing = _getListingById(listingsSet.at(i));
            if (listing.lenderAddress == msg.sender) {
                ownerListings[j] = listing;
                j++;
            }
        }
        return ownerListings;
    }

    // [Feature 2] Lender's dashboard
    // Lender can list NFT and store all this information in Listing
    function listNFT(uint256 tokenId, address tokenAddress, uint16 duration, uint16 dailyInterestRate, uint256 collateralRequired) public {
        // TODO: this is basic functionality to enable testing. Need to add validation etc. for public use.
        Listing memory listing = Listing ({
            id: 0,  // will be assigned by _addListing()
            tokenId: tokenId,
            tokenAddress: tokenAddress,
            lenderAddress: payable(msg.sender),
            duration: duration,
            dailyInterestRate: dailyInterestRate,
            collateralRequired: collateralRequired,
            rental: Rental({
                borrowerAddress: payable(0),
                rentedAt: 0
            })
        });

        validateListingNFT(listing);

        _addListing(listing);

        emit ListNFT(listing.tokenId);
    }

    /// [Feature 2] Lender's dashboard
    // Lender can unlist NFT and this listing is removed from the map/storage
    function unlistNFT(uint256 listingId) public {
        require(_listingExists(listingId), "listing does not exist");

        _deleteListing(listingId);

        emit UnlistNFT(listingId);
    }

    // [Feature 2] Lender's dashboard
    // Lender can unlist NFT and this listing is removed from the map/storage
    function terminateRental(uint256 listingId) public {
        Listing storage listing = _getListingById(listingId);
        validateListingNFT(listing);
        require(listing.lenderAddress == msg.sender, "only the lender can terminate the rental");
        uint dueDate = listing.rental.rentedAt + listing.duration * 86400;
        require(block.timestamp >= dueDate, "cannot terminate rental that is not yet due");
        uint payment = _calculatePayment(listing);
        _deleteListing(listingId);
        (bool sent,) = msg.sender.call{ value: payment }("");
        require(sent, "failed to send collateral back to lender");
        emit TerminateRental(listingId);
    }

    // [Feature 3] Borrower's dashboard
    // borrower can see all the NFTs they borrowed
    function viewRentedListings() public view returns (Listing[] memory){
        // Note: Dynamic arrays are not allowed unless they are storage
        // so we need to allocate a statically sized-array to return.
        // We can probably optimize this, but this should functionally work for now.
        uint listingsRented = 0;
        for (uint i = 0; i < listingsSet.length(); i++) {
            Listing memory listing = _getListingById(listingsSet.at(i));
            if (listing.rental.borrowerAddress == msg.sender) {
                listingsRented++;
            }
        }
        Listing[] memory rentedListings = new Listing[](listingsRented);
        uint j = 0;
        for (uint i = 0; i < listingsSet.length(); i++) {
            Listing memory listing = _getListingById(listingsSet.at(i));
            if (listing.rental.borrowerAddress == msg.sender) {
                rentedListings[j] = listing;
                j++;
            }
        }
        return rentedListings;
    }

    // [Feature 3] Borrower's dashboard
    // After borrower return NFT, collateral is sent from smart contract to borrower's address
    function returnNFT(uint256 listingId) public {
        Listing memory listing = _getListingById(listingId);
        require(listing.id != 0, "listingID was not found");
        IERC721(listing.tokenAddress).safeTransferFrom(listing.rental.borrowerAddress,
                                                       listing.lenderAddress,
                                                       listing.tokenId);
        (bool sent,) = payable(listing.rental.borrowerAddress).call{value: listing.collateralRequired}("");
        require(sent, "failed to send collateral back to borrower");
        uint elapsedRentalTime = block.timestamp - listing.rental.rentedAt;
        uint256 interestAmount = artStorage._calculateInterest(_getListingById(listingId), elapsedRentalTime);
        payable(listing.lenderAddress).call{value: interestAmount};
        _deleteListing(listingId);
        emit Returned(listingId);
    }

    // helper functions
    function validateListingNFT(Listing memory listing) private pure {
        require(listing.tokenId != 0, "validateListingNFT:: TokenId cannot be empty");
        require(listing.tokenAddress != address(0), "validateListingNFT:: TokenAddress cannot be empty");
        require(listing.duration > 0, "validateListingNFT:: Duration cannot be zero");
        require(listing.dailyInterestRate > 0, "validateListingNFT:: Daily interest rate cannot be zero");
        require(listing.collateralRequired > 0, "validateListingNFT:: Collateral cannot be zero");
    }

}
