// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error NftMarketplace__PriceMustBeAboveZero();
error NftMarketplace__NotApprovedForMarketplace();
error NftMarketplace__AlreadyListed(address nftAddress, uint256 tokenId);
error NftMarketplace__NotListed(address nftAddress, uint256 tokenId);
error NftMarketplace__NotOwner();
error NftMarketplace__PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error NftMarketplace__NoProceeds();
error NftMarketplace__TransferFailed();

contract NftMarketplace is ReentrancyGuard {

    /////////////////////
    //     structs     //
    /////////////////////

    struct Listing {
        uint256 price;
        address seller;
        }

    //////////////////////
    //      events      //
    //////////////////////

    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
        );

    event ItemBought(
        address indexed seller, 
        address indexed nftAddress, 
        uint256 indexed tokenId,
        uint256 price
        );

    event ItemCanceled (
        address indexed seller, 
        address indexed nftAddress, 
        uint256 indexed tokenId
        );

    //////////////////////
    //     mappings     //
    //////////////////////

    // NFT contract address -> NFT TokenId -> Listing
    mapping(address => mapping(uint256 => Listing)) private s_listings;

    // Seller address -> Amount earned
    mapping(address => uint256) private s_proceeds;

    /////////////////////
    //    Modifiers    //
    /////////////////////

    modifier notListed(address nftAddress, uint256 tokenId, address owner) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0) {
            revert NftMarketplace__AlreadyListed(nftAddress, tokenId);
        }
        _;
        }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NftMarketplace__NotListed(nftAddress, tokenId);
        }
        _;
        }

    modifier isOwner(
        address nftAddress, 
        uint256 tokenId, 
        address spender
        ) {
            IERC721 nft = IERC721(nftAddress);
            address owner = nft.ownerOf(tokenId);
            if (spender != owner) {
                revert NftMarketplace__NotOwner();
            }
            _;
        }

    ////////////////////
    // Main Functions //
    ////////////////////

// 1. `listItem`: List NFTs on the marketplace.
    /*
    * @notice Method for listing your NFT on the marketplace
    * @param nftAddress: Address of the NFT
    * @param tkenId: The token Id of the NFT
    * @param: price: sale price of the listed NFT
    * @dev Technically, we could have the contract be the escrow for the NFTs
    * but this way people can still hold their NFTs when listed.
    */
    function listItem(
        address nftAddress, 
        uint256 tokenId, 
        uint256 price // IMPROVE :could add another param address tokenPayment - chainlink price feeds
                      // to have this contract accept payments in a subset of tokens as well.
                      // using chainlink price feeds to convert the price of the tokens between each other
        ) 
        external 
        notListed(nftAddress, tokenId, msg.sender) 
        isOwner(nftAddress, tokenId, msg.sender)
        {
            if (price <= 0) {
                revert NftMarketplace__PriceMustBeAboveZero();
            }
            // 1. Send the NFT to the contract. Transfer --> Contract "hold" the NFT. ⛔️

            // 2. Owners can still hold their NFT, and give the marketplace approval
            // to sell the NFT for them. ✅

            IERC721 nft = IERC721(nftAddress);
            if (nft.getApproved(tokenId) != address(this)) {
                revert NftMarketplace__NotApprovedForMarketplace();
            }
            s_listings[nftAddress][tokenId] = Listing(price, msg.sender);
            emit ItemListed(msg.sender, nftAddress, tokenId, price);
        }

// 2. `buyItem`: Buy the NFTs.
    function buyItem (
        address nftAddress, 
        uint256 tokenId
        ) 
        external 
        payable 
        nonReentrant
        isListed(nftAddress, tokenId)
        {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        if (msg.value < listedItem.price) {
            revert NftMarketplace__PriceNotMet(nftAddress, tokenId, listedItem.price);
        }

        // We don't just send the seller the money --> PULL OVER PUSH.

        // Sending the money to the user ⛔️.
        // Have them withdraw the money ✅.
        s_proceeds[listedItem.seller] = s_proceeds[listedItem.seller] + msg.value;
        delete s_listings[nftAddress][tokenId];
        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);

        // Check to make sure the NFT was transferred.
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
        }

// 3. `cancelItem`: Cancel a listing.
    function cancelListing (
        address nftAddress, 
        uint256 tokenId
        ) 
        external 
        isOwner(nftAddress, tokenId, msg.sender) 
        isListed(nftAddress, tokenId)
        {
            delete (s_listings[nftAddress][tokenId]);
            emit ItemCanceled(msg.sender, nftAddress, tokenId);
        }

// 4. `updateListing`: Update price.
    function updateListing (
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
        )
        external
        isOwner(nftAddress, tokenId, msg.sender)
        isListed(nftAddress, tokenId)
        {
            s_listings[nftAddress][tokenId].price = newPrice;
            emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
        }

// 5. `withdrawProceeds`: Withdraw payment for my bought NFTs.
    function withdrawProceeds () external {
        uint256 proceeds = s_proceeds[msg.sender];
        if (proceeds <= 0){
            revert NftMarketplace__NoProceeds();
        }
        s_proceeds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: proceeds}("");
        if (!success) {
            revert NftMarketplace__TransferFailed();
        }
    }

    //////////////////////
    // Getter Functions //
    //////////////////////

    function getListing (
        address nftAddress, uint256 tokenId
        )
        external
        view
        returns(Listing memory)
        {
            return s_listings[nftAddress][tokenId];
        }

    function getProceeds (
            address seller
        )
        external
        view
        returns(uint256)
        {
            return s_proceeds[seller];
        }
}